require 'xcodeproj'
require 'pathname'
class Xcode
  def initialize()

  end

  def process
    project = Xcodeproj::Project.open("/Users/wuwenqiu/PrepareLipo/AutoPack/Example/AutoPack.xcodeproj")
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
    binary_target = project.new_target(:static_library, target_name, :ios)
    # 递归获取所有源文件
    source_files = Dir.glob(project.project_dir.parent.join("#{project_name}/Classes/**/*.{h,m}"))
    # 二进制target新建group引用源文件
    group = project.main_group.find_subpath(File.join(target_name, 'BinaryGroup'), true)
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
    write_shell(project_name + "Binary")
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
  def write_shell(target_name)
    # 打开组件主目录

    # 新建shell脚本

    # 写入打包代码
  end

end

Xcode.new().process
