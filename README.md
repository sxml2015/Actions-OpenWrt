小白 搬运 https://github.com/HoldOnBro/Actions-OpenWrt

折腾备注 


【1】
生成新令牌

1 个人中心：设置→开发人员设置→个人访问令牌→生成新令牌

 （名称：RELEASES_TOKEN，勾择：public_repo，复制RELEASES_TOKEN令牌的值）。
 
    Settings → Developer settings → Personal access tokens → Generate new token

2 操作代码中心：设置→机密→新机密（名称：RELEASES_TOKEN，值：粘贴令牌的值）。

   Settings → Secrets → New secret

如果需要telegram，电报推送消息 设置方法

   https://github.com/danshui-git/shuoming/blob/master/bot.md 
   
  .yml文件里开启
    
    #- name: Telegram notification
    
      
【2】在Releases  新建标签 Files4Compile 

手动上传 F大 打包文件

新的

boot-5.4.113-flippy-xxx+o.tar

boot-5.10.31-flippy-xxx+.tar

dtb-allwinner-5.4.113-flippy-xxx+o.tar

dtb-allwinner-5.10.31-flippy-xxx+.tar

dtb-amlogic-5.4.113-flippy-xxx+o.tar

dtb-amlogic-5.10.31-flippy-xxx+.tar

dtb-rockchip-5.4.113-flippy-xxx+o.tar

dtb-rockchip-5.10.31-flippy-xxx+.tar

modules-5.4.113-flippy-xxx+o.tar

modules-5.10.31-flippy-xxx+.tar

mk_openwrt_src_xxx.tar


旧的

#1.mk_openwrt_src_xxx.tar.gz   /打包工具 

#2.Armbian_20.10_Aml-s9xxx_buster_5.4.83-flippy-50+o.img.xz  / Armbian +o 文件

#3.Armbian_20.10_Aml-s9xxx_buster_5.9.14-flippy-50+.img.xz   / Armbian + 文件




【3】获取 Files4Compile  ID

github账号 Actions-OpenWrt 项目名 sxml2015/Actions-OpenWrt

https://api.github.com/repos/sxml2015/Actions-OpenWrt/releases 


修改 aarch64/getImgs.sh

wget $(curl -s https://api.github.com/repos/sxml2015/Actions-OpenWrt/releases/39391954 | grep browser_download_url | cut -d '"' -f 4)


【4】Actions 运行 

  ARMv8_SFE.yml 编译
  
  ARMv8_FOL.yml 编译 


【5】获取 Files4Build ID  修改ARMv8_Build.yml

https://api.github.com/repos/sxml2015/Actions-OpenWrt/releases


修改 ARMv8_Build.yml  ID

 sudo wget $(curl -s https://api.github.com/repos/sxml2015/Actions-OpenWrt/releases/39397290 | grep browser_download_url | cut -d '"' -f 4)


【6】运行 ARMv8_Build.yml 打包 


-------------------------------------------------------------------------
Actions 运行 ARMv8_SFE.yml

SSH 连接操作

Actions→ 选择xxx.yml→ 然后单击Run workflow右侧的按钮。设置SSH connection to Actions: true →点 Run workflow 运行

页面运行到SSH connection to Actions 点击显示的连接 进入SSH

（Web终端可能会遇到黑屏，只需按即可Ctrl+C）

输入命令：cd openwrt && make menuconfig 进行个性化配置。

完成后，按快捷键Ctrl+D或执行exit命令以退出，随后的编译工作将自动进行

-------------------------------------------------------------------------

云编译说明 https://github.com/danshui-git/shuoming
