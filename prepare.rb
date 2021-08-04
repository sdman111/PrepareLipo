require 'xcodeproj'
require 'pathname'
require 'optparse'

class Xcode
  def initialize(path)
    @path = path
  end

  def process
    project = Xcodeproj::Project.open(@path)
    project_name = File.basename(project.path,".xcodeproj")
    process_binary_target(project, project_name)
    process_aggregate_target(project, project_name)
    project.save
  end

  # 处理binary target
  def process_binary_target(project, project_name)
    target_name = project_name + "Binary"
    # 删除二进制target
    del_target(project, target_name)
    # 新建二进制target
    binary_target = project.new_target(:static_library, target_name, :ios, nil, project.products_group)
    # 设置product name(修改target的build settings)
    binary_target.build_configurations.each { |build_configuration|
      # 获取build settings
      build_settings = build_configuration.build_settings
      # 设置product name
      build_settings["PRODUCT_NAME"] = target_name
    }
    # 递归获取所有源文件
    source_files = Dir.glob(project.project_dir.parent.join("#{project_name}/Classes/**/*.{h,m}"))
    # 二进制target新建group引用源文件
    group = project.main_group.find_subpath(File.join(target_name, ''), true)
    # 清空原有group引用
    unless group.empty?
      removeBuildPhaseFilesRecursively(binary_target, group)
      group.clear
    end
    group.set_source_tree('SOURCE_ROOT')
    # 添加新的源文件引用
    source_files.each do |file|
      file_ref = group.new_reference(file)
      binary_target.add_file_references([file_ref])
    end
    # 新建Binary目录保存打包文件
    binary_folder = project.project_dir.join target_name
    unless Dir.exist? binary_folder
      Dir.mkdir binary_folder
    end
  end

  # 处理aggregate target
  def process_aggregate_target(project, project_name)
    target_name = project_name + "BinaryScript"
    # 删除原有aggregate target
    del_target(project, target_name)
    # 新建aggregate target
    aggregate_target = project.new_aggregate_target(target_name)
    # 设置Build Phase,添加Run Script
    aggregate_target.new_shell_script_build_phase("Run build.sh Script")
    # 初始化build.sh
    if write_shell(project, project_name + "Binary")
      puts "初始化build.sh打包脚本✅"
    end
    # 设置shell_script内容
    aggregate_target.shell_script_build_phases.first.shell_script = "sh ../build.sh"
  end

  # 删除原有target
  def del_target(project, target_name)
    project.targets.each_with_index do |target, index|
      if target.name == target_name
        puts "覆盖原有target: #{target_name}"
        project.targets.delete_at(index)
        break
      end
    end
  end

  # 删除target对group资源的引用
  def removeBuildPhaseFilesRecursively(aTarget, aGroup)
    aGroup.files.each do |file|
      if file.real_path.to_s.end_with?(".m", ".mm", ".cpp") then
        aTarget.source_build_phase.remove_file_reference(file)
      elsif file.real_path.to_s.end_with?(".plist") then
        aTarget.resources_build_phase.remove_file_reference(file)
      end
    end
    aGroup.groups.each do |group|
      removeBuildPhaseFilesRecursively(aTarget, group)
    end
  end

  # 初始化打包shell脚本内容
  def write_shell(project, binary_target_name)
    # 打开组件主目录
    dir_name = project.project_dir.parent
    # 新建shell脚本
    build_sh = File.open(dir_name.join("build.sh"),"w+") do |file|
    file.puts <<EOF # 利用块写入打包代码
set -e
set +u
### Avoid recursively calling this script.
if [[ $UF_MASTER_SCRIPT_RUNNING ]]
then
exit 0
fi
set -u
export UF_MASTER_SCRIPT_RUNNING=1
### Constants.
# 静态库target对应的scheme名称
SCHEMENAME="#{binary_target_name}"
# .a与头文件生成的目录，在项目中的HBAuthenticationBinary目录下的Products目录中
BASEBUILDDIR=$PWD/${SCHEMENAME}/Products
rm -fr "${BASEBUILDDIR}"
mkdir "${BASEBUILDDIR}"
# 支持全架构的二进制文件目录
UNIVERSAL_OUTPUTFOLDER=${BASEBUILDDIR}/Binary-universal
# 支持真机的二进制文件目录
IPHONE_DEVICE_BUILD_DIR=${BASEBUILDDIR}/Binary-iphoneos
# 支持模拟器的二进制文件目录
IPHONE_SIMULATOR_BUILD_DIR=${BASEBUILDDIR}/Binary-iphonesimulator
### Functions
## List files in the specified directory, storing to the specified array.
#
# @param $1 The path to list
# @param $2 The name of the array to fill
#
##
list_files ()
{
    filelist=$(ls "$1")
    while read line
    do
        eval "$2[\\${\#$2[*]}]=\\"\\$line\\""
    done <<< "$filelist"
}
### Take build target.
if [[ "$SDK_NAME" =~ ([A-Za-z]+) ]]
then
SF_SDK_PLATFORM=${BASH_REMATCH[1]} # "iphoneos" or "iphonesimulator".
else
echo "Could not find platform name from SDK_NAME: $SDK_NAME"
exit 1
fi
echo "===== 构建x86_64架构 ====="
xcodebuild -workspace "${PROJECT_NAME}.xcworkspace" -scheme "${SCHEMENAME}" -configuration "${CONFIGURATION}" -sdk iphonesimulator CONFIGURATION_BUILD_DIR="${IPHONE_SIMULATOR_BUILD_DIR}/x86_64" OBJROOT="${OBJROOT}/DependantBuilds" ARCHS='x86_64' VALID_ARCHS='x86_64' $ACTION
# Build device platform. (armv7, arm64)
echo "========== Build Device Platform =========="
echo "===== Build Device Platform: armv7 ====="
xcodebuild -workspace "${PROJECT_NAME}.xcworkspace" -scheme "${SCHEMENAME}" -configuration "${CONFIGURATION}" -sdk iphoneos CONFIGURATION_BUILD_DIR="${IPHONE_DEVICE_BUILD_DIR}/armv7" ARCHS='armv7 armv7s' VALID_ARCHS='armv7 armv7s' OBJROOT="${OBJROOT}/DependantBuilds" $ACTION
echo "===== Build Device Platform: arm64 ====="
xcodebuild -workspace "${PROJECT_NAME}.xcworkspace" -scheme "${SCHEMENAME}" -configuration "${CONFIGURATION}" -sdk iphoneos CONFIGURATION_BUILD_DIR="${IPHONE_DEVICE_BUILD_DIR}/arm64" ARCHS='arm64' VALID_ARCHS='arm64' OBJROOT="${OBJROOT}/DependantBuilds" $ACTION
### Build universal platform.
echo "========== Build Universal Platform =========="
## Copy the framework structure to the universal folder (clean it first).
rm -rf "${UNIVERSAL_OUTPUTFOLDER}"
mkdir -p "${UNIVERSAL_OUTPUTFOLDER}"
## Copy the last product files of xcodebuild command.
cp -R "${IPHONE_DEVICE_BUILD_DIR}/arm64/lib${SCHEMENAME}.a" "${UNIVERSAL_OUTPUTFOLDER}/lib${SCHEMENAME}.a"
### Smash them together to combine all architectures.
lipo -create "${IPHONE_SIMULATOR_BUILD_DIR}/x86_64/lib${SCHEMENAME}.a" "${IPHONE_DEVICE_BUILD_DIR}/armv7/lib${SCHEMENAME}.a" "${IPHONE_DEVICE_BUILD_DIR}/arm64/lib${SCHEMENAME}.a" -output "${UNIVERSAL_OUTPUTFOLDER}/lib${SCHEMENAME}.a"

echo "========== Create Standard Structure =========="
cp -r "${IPHONE_DEVICE_BUILD_DIR}/arm64/usr/local/include/" "${UNIVERSAL_OUTPUTFOLDER}/include/"
EOF
    end
    1
  end

end

options = {}
option_parser = OptionParser.new do |opts|
  opts.banner = '命令行帮助信息'
  opts.on('-p xcodeproj_path', '--podfile xcodeproj_path', 'Where the xcodeproj is 必要参数:组件xcodeproj的绝对路径') do |value|
    options[:path] = value
  end
end.parse!

processor = Xcode.new(options[:path])
processor.process
