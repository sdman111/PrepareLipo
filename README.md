# PrepareLipo
释放二进制打包前的人工操作

## 使用方式

ruby prepare.rb -p [组件xcodeproj绝对路径]



## 脚本替代的过程

1. 二进制target的新建以及源码的引用
2. aggregate target的新建以及build phase的设置
3. 组件目录build.sh打包脚本的新建



## 脚本运行后人工操作部分

1. 设置组件工程中后缀为Binary的binary target引用头文件需要暴露的头文件部分
2. target切换为Script后缀的aggregate target并进行编译
