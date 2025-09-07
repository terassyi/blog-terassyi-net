+++
categories = [ "tech" ]
tags = [ "xdp", "ebpf", "vagrant" ]
date = 2020-10-19
title = "XDPが実行できるVagrantfileを探して"
description = "XDPが実行できるVagrantfileを作ってXDPに入門します"
+++

こんにちは．大学院の後期授業も開始され，さらに多数イベントが同時並行で開催されており非常に忙しい日々を過ごしています．最近は将棋の勉強にも精を出しています．弱いですが．
今回はXDPが実行できるVMをVagrantで作ります．
先日[GMOペパボさんのeBPFインターンシップ](https://terassyi.net/posts/2020/09/12/pepabo-intern.html)に参加させていただいて以降eBPF関連の技術に興味を持っておりXDPに手を出してみます．

<!--more-->

## XDPとは
`XDP`とは`eXpress Data Pass`の略で高速にパケット処理を行うことのできるLinuxカーネルの機能です(語彙力)．
私自身まだ入門もしていないので詳しい説明は別の記事にまかせます．
- [Linuxカーネルの新機能 XDP (eXpress Data Path) を触ってみる](http://yunazuno.hatenablog.com/entry/2016/10/11/090245)

## XDPに対応したVMを探して
`xdp vagrant`などで検索すると[github.com/iovisor/xdp-vagrant](https://github.com/iovisor/xdp-vagrant)こちらのリポジトリに当たりますがこちらのVMは依存関係が解決できずうまくサンプルを実行できませんでした．さらに[github.com/xdp-project/xdp-tutorial](https://github.com/xdp-project/xdp-tutorial)が見つかりますがこちらもbasic02あたりからつまずきます．そのほかいろいろネットを徘徊してみましたがいいものが見つかりません．

### ないので作る
適切なものが見つからないので作ることにしました．作るといってもベースは先ほどの[github.com/iovisor/xdp-vagrant](https://github.com/iovisor/xdp-vagrant)を流用させていただきました．使用するboxを`generic/ubuntu2004`に変更しています．

作ったVagrantfileは[こちらのgist](https://gist.github.com/terassyi/41937fb488361c3aeb75425de07426f8)においてます．


- Vagrantfile
    ポイントは`libvirt.nic_model_type = "e1000"`です．XDPに対応したNICを選択する必要がありますね．
    ```
    ['vagrant-reload'].each do |plugin|
    unless Vagrant.has_plugin?(plugin)
        raise "Vagrant plugin #{plugin} is not installed!"
    end
    end

    Vagrant.configure('2') do |config|
    config.vm.box = "generic/ubuntu2004" # Ubuntu
    config.vm.network "private_network", ip: "192.168.50.4"

    # fix issues with slow dns https://www.virtualbox.org/ticket/13002
    config.vm.provider :libvirt do |libvirt|
        libvirt.connect_via_ssh = false
        libvirt.memory = 1024
        libvirt.cpus = 2
        libvirt.nic_model_type = "e1000"
    end
    config.vm.synced_folder "./", "/home/vagrant/work"
    config.vm.provision :shell, :privileged => true, :path => "setup.sh"
    end
    ```
- setup.sh
    vmの起動時に実行されるスクリプトです．xdpのコードをビルドするためのソフト類を入れています．こちらのファイルは[bcc python tutorial](https://github.com/iovisor/bcc/blob/master/INSTALL.md)を元に作成しています．
    ```shell
    #!/bin/bash

    sudo apt update -y

    sudo apt install -y bison build-essential cmake flex git libedit-dev \
    libllvm7 llvm-7-dev libclang-7-dev python zlib1g-dev libelf-dev \
    python3-distutils clang

    git clone https://github.com/iovisor/bcc.git
    mkdir bcc/build; cd bcc/build
    cmake ..
    make
    sudo make install
    cmake -DPYTHON_CMD=python3 .. # build python3 binding
    pushd src/python/
    make
    sudo make install
    popd

    # install golang
    wget https://golang.org/dl/go1.15.3.linux-amd64.tar.gz
    sudo tar -C /usr/local -xzf go1.15.3.linux-amd64.tar.gz
    rm -rf go1.15.3.linux-amd64.tar.gz
    ```

### 実行
```
$ vagrant init generic/ubuntu2004
```
した後，
```
$ vagrant up
```
で起動して
```
$ vagrant ssh
```
でVMに接続します．

## まとめ
カーネルのバージョンやpythonの依存関係に悩まされましたがこれでやっとXDPに入門することができます．
XDP使ってみた系の資料はまだ少ないのでブログ書きたいと思います．
