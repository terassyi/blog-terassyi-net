+++
categories = [ "tech" ]
tags = [ "container", "runc", "golang", "OCI-runtime" ]
date = 2020-05-08
title = "自作コンテナランタイムでつまずいてる話"
description = "自作コンテナランタイムに挑戦しています．しかし，なかなかエラーが解決しないので現状についてまとめます．"
+++
こんにちは．緊急事態宣言がのびたので相変わらずの外出自粛中です．最近は外出自粛にも少し慣れましたがやはり退屈です．僕は作業中のBGMとして何度か見たことのあるアニメなどを流しているんですがそれらのストックも無くなってきています．ループしようかな．ちなみにおすすめはガンダムUCですね．音楽が素晴らしいですし，SFアニメはモチベが上がっていいです．
さて，今回は自作コンテナランタイムに挑戦したという話です．[前回のポスト](https://terassyi.net/posts/2020/04/29/runc.html)では`runc`を使ってみましたが，今回は`runc`を参考に挑戦してみました．

ちなみにコード書いて試してたときに`rm -rf`で書いてたコード全消去して萎えました．
{{<x user="terassyi_" id="1256486345381261313" >}}

gitで管理するのって大事ですね．
リポジトリはこちら

{{<github repo="terassyi/mycon">}}

## タイトルについて

タイトルにつまずいているとつけましたが，つまずいてます．長い間同じ箇所でエラーがでて前に進めていません．
僕の魂の叫びがこちら．

{{<x user="terassyi_" id="1258671454658289664">}}

このあと力付きこの記事を書き始めております．
ツイートの通り，マウントでつまずいております．
どなたか有識者の方に助けていただきたいです．

## 問題

発生している問題は
>　`rootfs/dev/pts`に`devpts`でマウントできない

という問題です．
コンテナプロセスの設定ファイルである`config.json`でいうと以下の部分です．

```json
{
	"destination": "/dev/pts",
	"type": "devpts",
	"source": "devpts",
	"options": [
		"rw",
		"mode=0620",
		"gid=5"
	]
},
```

実際にマウントを行うのは以下のコードです．
標準パッケージのマウントシステムコールのラッパー関数を呼び出しています．

```go
if err := unix.Mount(m.Source, target, m.Type, uintptr(flags), data); err != nil {
	return err
}
```

`unix.Mount`メソッドに

- m.Source = devpts
- target = rootfs/dev/ptsへの絶対パス
- m.Type = devpts
- flags = 0(オプションから得られるフラグ)
- data = mode=0620,gid=5

という感じで引数を渡しています．
すると`Invalid argument`エラーを発生させます．

```
DEBU[0000] source=devpts
DEBU[0000] target=/usr/local/go/src/github.com/terassyi/mycon/bundle/rootfs/dev/pts
DEBU[0000] mtype=devpts
DEBU[0000] flags=0
DEBU[0000] options=mode=0620,gid=5
DEBU[0000] invalid argument
```

### 問題の実験環境

詳しくは後述しますが，実験しているVMのイメージは[ubuntu/xenial64](https://app.vagrantup.com/ubuntu/boxes/xenial64)です．
ルート直下の構成は以下の様な感じ

```
$ ls /
bin   dev  home        initrd.img.old  lib64       media  opt   root  sbin  srv  tmp  vagrant  vmlinuz
boot  etc  initrd.img  lib             lost+found  mnt    proc  run   snap  sys  usr  var      vmlinuz.old
```

また，コンテナプロセスとして起動しようとしているのはdockerイメージからエクスポートしたcentosです．
プロジェクトから`./bundle/rootfs/`以下にファイルを配置しています．

#### マウントされているファイルシステム

マウントされているファイルシステムは以下の様な感じ.

```
$ mount
sysfs on /sys type sysfs (rw,nosuid,nodev,noexec,relatime)
proc on /proc type proc (rw,nosuid,nodev,noexec,relatime)
udev on /dev type devtmpfs (rw,nosuid,relatime,size=498852k,nr_inodes=124713,mode=755)
devpts on /dev/pts type devpts (rw,nosuid,noexec,relatime,mode=600,ptmxmode=000)
tmpfs on /run type tmpfs (rw,nosuid,noexec,relatime,size=101576k,mode=755)
/dev/sda1 on / type ext4 (rw,relatime,data=ordered)
securityfs on /sys/kernel/security type securityfs (rw,nosuid,nodev,noexec,relatime)
tmpfs on /dev/shm type tmpfs (rw,nosuid,nodev)
tmpfs on /run/lock type tmpfs (rw,nosuid,nodev,noexec,relatime,size=5120k)
tmpfs on /sys/fs/cgroup type tmpfs (ro,nosuid,nodev,noexec,mode=755)
cgroup on /sys/fs/cgroup/systemd type cgroup (rw,nosuid,nodev,noexec,relatime,xattr,release_agent=/lib/systemd/systemd-cgroups-agent,name=systemd)
pstore on /sys/fs/pstore type pstore (rw,nosuid,nodev,noexec,relatime)
cgroup on /sys/fs/cgroup/perf_event type cgroup (rw,nosuid,nodev,noexec,relatime,perf_event)
cgroup on /sys/fs/cgroup/freezer type cgroup (rw,nosuid,nodev,noexec,relatime,freezer)
cgroup on /sys/fs/cgroup/memory type cgroup (rw,nosuid,nodev,noexec,relatime,memory)
cgroup on /sys/fs/cgroup/devices type cgroup (rw,nosuid,nodev,noexec,relatime,devices)
cgroup on /sys/fs/cgroup/cpu,cpuacct type cgroup (rw,nosuid,nodev,noexec,relatime,cpu,cpuacct)
cgroup on /sys/fs/cgroup/net_cls,net_prio type cgroup (rw,nosuid,nodev,noexec,relatime,net_cls,net_prio)
cgroup on /sys/fs/cgroup/pids type cgroup (rw,nosuid,nodev,noexec,relatime,pids)
cgroup on /sys/fs/cgroup/blkio type cgroup (rw,nosuid,nodev,noexec,relatime,blkio)
cgroup on /sys/fs/cgroup/hugetlb type cgroup (rw,nosuid,nodev,noexec,relatime,hugetlb)
cgroup on /sys/fs/cgroup/cpuset type cgroup (rw,nosuid,nodev,noexec,relatime,cpuset)
mqueue on /dev/mqueue type mqueue (rw,relatime)
systemd-1 on /proc/sys/fs/binfmt_misc type autofs (rw,relatime,fd=33,pgrp=1,timeout=0,minproto=5,maxproto=5,direct)
hugetlbfs on /dev/hugepages type hugetlbfs (rw,relatime)
debugfs on /sys/kernel/debug type debugfs (rw,relatime)
fusectl on /sys/fs/fuse/connections type fusectl (rw,relatime)
lxcfs on /var/lib/lxcfs type fuse.lxcfs (rw,nosuid,nodev,relatime,user_id=0,group_id=0,allow_other)
vagrant on /vagrant type vboxsf (rw,nodev,relatime)
usr_local_go_src_github.com_terassyi_mycon on /usr/local/go/src/github.com/terassyi/mycon type vboxsf (rw,nodev,relatime)
tmpfs on /run/user/1000 type tmpfs (rw,nosuid,nodev,relatime,size=101576k,mode=700,uid=1000,gid=1000)
binfmt_misc on /proc/sys/fs/binfmt_misc type binfmt_misc (rw,relatime)
devpts on /usr/local/pts type devpts (rw,relatime,mode=600,ptmxmode=000)
usr_local_go_src_github.com_terassyi_mycon on /usr/local/go/src/github.com/terassyi/mycon/bundle/rootfs type vboxsf (rw,nodev,relatime)
```

```
$ df -aH
Filesystem                                  Size  Used Avail Use% Mounted on
sysfs                                          0     0     0    - /sys
proc                                           0     0     0    - /proc
udev                                        511M     0  511M   0% /dev
devpts                                         0     0     0    - /dev/pts
tmpfs                                       105M  3.3M  101M   4% /run
/dev/sda1                                    11G  1.8G  8.7G  17% /
securityfs                                     0     0     0    - /sys/kernel/security
tmpfs                                       521M     0  521M   0% /dev/shm
tmpfs                                       5.3M     0  5.3M   0% /run/lock
tmpfs                                       521M     0  521M   0% /sys/fs/cgroup
cgroup                                         0     0     0    - /sys/fs/cgroup/systemd
pstore                                         0     0     0    - /sys/fs/pstore
cgroup                                         0     0     0    - /sys/fs/cgroup/perf_event
cgroup                                         0     0     0    - /sys/fs/cgroup/freezer
cgroup                                         0     0     0    - /sys/fs/cgroup/memory
cgroup                                         0     0     0    - /sys/fs/cgroup/devices
cgroup                                         0     0     0    - /sys/fs/cgroup/cpu,cpuacct
cgroup                                         0     0     0    - /sys/fs/cgroup/net_cls,net_prio
cgroup                                         0     0     0    - /sys/fs/cgroup/pids
cgroup                                         0     0     0    - /sys/fs/cgroup/blkio
cgroup                                         0     0     0    - /sys/fs/cgroup/hugetlb
cgroup                                         0     0     0    - /sys/fs/cgroup/cpuset
mqueue                                         0     0     0    - /dev/mqueue
systemd-1                                      -     -     -    - /proc/sys/fs/binfmt_misc
hugetlbfs                                      0     0     0    - /dev/hugepages
debugfs                                        0     0     0    - /sys/kernel/debug
fusectl                                        0     0     0    - /sys/fs/fuse/connections
lxcfs                                          0     0     0    - /var/lib/lxcfs
vagrant                                     500G  370G  131G  74% /vagrant
usr_local_go_src_github.com_terassyi_mycon  500G  370G  131G  74% /usr/local/go/src/github.com/terassyi/mycon
tmpfs                                       105M     0  105M   0% /run/user/1000
binfmt_misc                                    0     0     0    - /proc/sys/fs/binfmt_misc
devpts                                         0     0     0    - /usr/local/pts
usr_local_go_src_github.com_terassyi_mycon  500G  370G  131G  74% /usr/local/go/src/github.com/terassyi/mycon/bundle/rootfs
```

また，コマンドラインから`mount`を実行した場合はうまくいっている様です．

```
$ sudo mount -vt devpts devpts ./dev/pts/ -o mode=0620,gid=5
mount: devpts mounted on /usr/local/go/src/github.com/terassyi/mycon/bundle/rootfs/dev/pts.
```

確認してみます．

```
$ mount | grep devpts
devpts on /dev/pts type devpts (rw,nosuid,noexec,relatime,gid=5,mode=620,ptmxmode=000)
devpts on /usr/local/pts type devpts (rw,relatime,gid=5,mode=620,ptmxmode=000)
devpts on /usr/local/go/src/github.com/terassyi/mycon/bundle/rootfs/dev/pts type devpts (rw,relatime,gid=5,mode=620,ptmxmode=000)
devpts on /usr/local/go/src/github.com/terassyi/mycon/bundle/rootfs/dev/pts type devpts (rw,relatime,gid=5,mode=620,ptmxmode=000)
```

```
/usr/local/go/src/github.com/terassyi/mycon/bundle/rootfs$ ls dev/pts
0  1  ptmx
```

マウントリストにも出てきて，かつlsコマンドで`dev/pts`を覗くと`/dev/pts/`と同様のファイルが見えるのでマウントが完了している様に見えます．
しかし，作成したプログラムから実行するとエラーを発生させます．
マウントする順番の問題やその他プログラムの問題である可能性も考えつつ調査をしていましたが，なかなか解決策が見当たりません．
Linuxについて理解不足であることは間違いないので，もし原因や解決策に心当たりのある方がいらっしゃったらご教授お願いしたいです．

## 自作コンテナの動機

皆さんdocker好きですか？僕は好きです．
普段Macを使用しているのですが，Linuxをターゲットにしたプログラムを書くことが多いです．そのようなときにdockerは非常に簡単にLinuxの環境を構築でき，また，リポジトリに一緒に入れておくことでもし誰かが試してみたいと思ったときにコマンド一つで環境が再現できます．最近はVagrantを使用して環境構築を行うこともありますが基本的にdockerの方が便利ですよね．
さてここで気になるのはdockerがどのように仮想環境を実現しているかです．
ざっくりLinuxの`namespace`や`cgroup`などの機能を使用して実現しているという理解はあったのですが，詳しくはわかりませんでした．
そこで，仕組みを理解するには作ってみることが一番ということで自作してみるか，となりました．
しかし，現実はそう甘くないです．

{{<x user="terassyi_" id="1254346873982222337">}}

{{<x user="terassyi_" id="1253256724741406721">}}

## 実験環境

今回はVagrantを使用してMac上にubuntu VMを起動して実行しました．IDEはGolandを使用しました．
Mac上でLinuxをターゲットとして定義ジャンプなどできるので便利です．

Vagrantfile

```
Vagrant.configure("2") do |config|

  config.vm.box = "ubuntu/xenial64"
  config.vm.synced_folder "./", "/usr/local/go/src/github.com/terassyi/mycon"
  config.vm.provision :shell, :path => "./install.sh"

end
```

install.sh

```
#! /bin/sh

sudo apt update

# install golang
wget https://dl.google.com/go/go1.14.2.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.14.2.linux-amd64.tar.gz
rm go1.14.2.linux-amd64.tar.gz

echo "export PATH=$PATH:/usr/local/go/bin" >> .bashrc

# install docker
sudo apt -y install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

sudo apt update
sudo apt -y install docker.io

sudo systemctl start docker

# add docker user group
sudo groupadd docker
sudo gpasswd -a $USER docker
sudo systemctl enable docker
```

さぁやりましょう．

## runcについて

まずは`runc`について．
runcでコンテナプロセスを作成するには`runc create [container id]`コマンドを実行します．
起動するには`runc start [container id]`ですね．
詳しくは[前回のポスト](https://terassyi.net/posts/2020/04/29/runc.html)を参照してください．

### runcがどのようにコンテナプロセスを起動するか

`runc create [container id]`を実行した後，runcはどのような処理を行ってコンテナプロセスが生成されるのでしょうか．
ここら辺を調べるためにruncのコードと格闘しました．
こちらの資料がすごく参考になりました．
[コンテナユーザなら誰もが使っているランタイム「runc」を俯瞰する[Container Runtime Meetup #1発表レポート]](https://medium.com/nttlabs/runc-overview-263b83164c98)
こちらの資料では`runc run`コマンドの実装について述べられています．runコマンドは新しいコンテナプロセスを生成して実行する`create + start`のようなコマンドなので基本的なフローはcreateの場合も同じです．
createコマンドが実行されると，内部で`runc init`というコマンドが名前空間を分離した上で別プロセスで実行されるようになっています．
その後，`init`プロセスにおいて，`cgroup`や`capabilities`，`pivot_root`などのリソース分離作業を行っています．
リソースの分離作業を終えると`start`コマンドからの起動シグナルを待ち受けてシグナルを受けるとセットされているコマンドを実行します．

### リソースの分離について

さて，リソースの分離とはどういったものでしょう．`namespace`や`cgroup`，`chroot`を使用しています．
[コンテナ技術入門 - 仮想化との違いを知り、要素技術を触って学ぼう](https://employment.en-japan.com/engineerhub/entry/2019/02/05/103000#Capability)では，仮想マシンとコンテナの違いからLinuxコマンドを使用したコンテナの作成まで丁寧に説明されています．(僕が説明するより断然わかりやすいのでこちらを覗いてみてください)
一度手を動かしてみると非常に理解が進みます．
`chroot`と`pivot_root`の違いなどわかりやすかったです．

## config.json

作成するコンテナの設定は全て`config.json`に記述されています．このファイルは`runc spec`を実行するとテンプレートが作成されます．
基本的には変更せずに使用します．
ファイルの中身は前回のポストを参照してください．
[config.json](https://terassyi.net/posts/2020/04/29/runc.html#config-json%E3%81%AE%E6%BA%96%E5%82%99)

コンテナプロセスを作成する際に`config.json`からコンテナ起動時のコマンドやマウントするディレクトリ，cgroupやlinux capabilitiesなどの設定を読み込んで作成します．

## 開発

それでは作成したプログラムをみていきます．
CLIアプリケーションとして作成するので[google/subcommands](https://github.com/google/subcommands)を使用しました．
こちらが`main.go`

```go
func main() {
	subcommands.Register(subcommands.FlagsCommand(), "")
	subcommands.Register(new(cmd.Create), "")
	subcommands.Register(new(cmd.Start), "")

	const internalOnly = "internal only"
	subcommands.Register(new(cmd.Init), internalOnly)

	flag.Parse()
	setDebugMode(debug)

	ctx := context.Background()
	os.Exit(int(subcommands.Execute(ctx)))
}
```
`subcommands.Command`インターフェースを満たした型のインスタンスを登録することでcreateなどのサブコマンドを扱えるようにします．
`init`サブコマンドは内部のみ呼び出されるべきなので`internal only`というラベルをつけています．
各種サブコマンドの実装は`cmd`以下に配置しています．

### create

まずは`create`をみてみましょう．
コマンドの中身は`Execute`メソッドに記述します．
主な処理は以下です．

- バンドルディレクトリ(`config.json`とコンテナのルートファイルシステムを配置する)を指定して`config.json`を読み込んで`specs.Spec`構造体にマッピング
- `init`サブコマンドを内部で呼び出すための`Factory`構造体のインスタンスを生成
- `Factory.Create`メソッドで`init`サブコマンドを別プロセスとして実行

順に処理内容をみてみます．

#### config.jsonとspces.Spec

`config.json`は[opencontainer/runtime-spec/specs-go](https://github.com/opencontainers/runtime-spec/blob/master/specs-go/config.go)の`specs.Spec`構造体にマッピングできます．
フィールドが大量にあるので今回はこれを流用しました．
そしてこれらを`Config`構造体にマッピングします．

```go
type Config struct {
	Id     string
	Bundle string
	Spec   *specs.Spec
}
```

#### initプロセスを作成するFactory構造体

`Factory`型には`create`を実行しているプロセスから`init`プロセスを起動するための構造体です．

```go
factory := &Factory{
		Id:       id,
		Pid:      -1,
		Root:     root,
		InitPath: "/proc/self/exe",
		InitArgs: []string{os.Args[0], "-debug", "init", id}, // path to mycon init
	}
```

`InitPath`には`/proc/self/exe`という文字列を渡していますが，これは現在実行中のプロセスへのパスを指すシンボリックリンクとなっています．
また`InitArgs`の`os.Args[0]`はコマンドライン引数の0番目なのでこの場合`./mycon`という実行ファイルを指していることとなります．
その後デバッグオプションをつけて`init`をサブコマンドとして指定しています．

#### Factory.Createメソッド

さて，どのように`init`プロセスを起動するのでしょう．
Createでは以下のような処理をしています．

- コンテナのルートディレクトリを作成
- bundleディレクトリに移動
- `init`プロセスと`start`コマンドのプロセス間でシグナルをやり取りするfifoファイル作成
- 実行するコマンドの作成と実行

具体的な処理は以下の様になってます．

#### コンテナルートディレクトリの作成

`/run/mycon/[container id]`というディレクトリを作成します．この中にコンテナ作成時に必要なファイルなどを配置します．これはコンテナに対して固有のディレクトリとなるので既に存在する場合はエラーを返します．

```go
containerRootPath := filepath.Join(f.Root, f.Id)
	if _, err := os.Stat(containerRootPath); err == nil {
		return nil, fmt.Errorf("container root dir is already exist")
	}
	// make container dir
	if err := os.MkdirAll(containerRootPath, 0711); err != nil {
		return nil, err
	}
```

#### bundleディレクトリに移動

```go
if err := os.Chdir(config.Bundle); err != nil {
		logrus.Debug("failed to chdir bundle dir: %v", err)
		return nil, err
	}
```

`bundle`で指定されたディレクトリに移動します．`bundle`はデフォルトではカントディレクトリです．

#### fifoファイルの作成

`mkfifo`で名前付きパイプを作成します．
名前付きパイプについては[こちら](https://kazmax.zpp.jp/cmd/f/fifo.7.html)を参照してください.
`init`プロセスと`start`プロセスで通信を行うのに使用します．

```go
if err := unix.Mkfifo(path, 0744); err != nil {
		return fmt.Errorf("failed to create fifo file: %v", err)
	}
```

#### mycon initを実行するコマンドを作成して実行

`init`プロセスを起動するためのコマンドを作成します．
`Factory`型インスタンスに登録されている`InitPath`, `InitArgs`を渡して`*exec.Cmd`を返します．
その際に各種名前空間を分離して，標準入力などを指定しています．

```go
// buildInitCommand builds a command to start init process
func (f *Factory) buildInitCommand() *exec.Cmd {
	cmd := exec.Command(f.InitPath, f.InitArgs[1:]...)
	cmd.SysProcAttr = &unix.SysProcAttr{
		Cloneflags: unix.CLONE_NEWIPC | unix.CLONE_NEWNET | unix.CLONE_NEWNS |
			unix.CLONE_NEWPID | unix.CLONE_NEWUSER | unix.CLONE_NEWUTS,
		UidMappings: []syscall.SysProcIDMap{
			{ContainerID: 0, HostID: os.Getuid(), Size: 1},
		},
		GidMappings: []syscall.SysProcIDMap{
			{ContainerID: 0, HostID: os.Getgid(), Size: 1},
		},
	}
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	logrus.Debugf(cmd.String())
	return cmd
}
```

また，作成した`cmd`にfifoファイルへのファイルディスクリプタを環境変数として格納します．

```go
func (f *Factory) setFifoFd(cmd *exec.Cmd) (int, error) {
	path := filepath.Join(f.Root, f.Id, fifoName)
	fd, err := unix.Open(path, unix.O_PATH|unix.O_CLOEXEC, 0)
	if err != nil {
		logrus.Debug(err)
		return -1, err
	}
	defer unix.Close(fd)
	cmd.ExtraFiles = append(cmd.ExtraFiles, os.NewFile(uintptr(fd), fifoName))
	cmd.Env = append(cmd.Env, fmt.Sprintf("_MYCON_FIFOFD=%v", fd+3+len(cmd.ExtraFiles)-1))
	return fd, err
}
```

その後，実行します．
これで`init`プロセスが起動することとなります．

### init

さて，`init`プロセスを起動しました．
次はこちらをみてみます．
`init`サブコマンドで実行される処理の実体は`cmd/init.go`にあります．
ここでは`Factory.Initialize`メソッドで具体的処理を行います．
`Factory`型のメソッドとして`Initialize`を定義しているのはruncがそうしていたからなんですが，今回のコードではあまり`Factory`型のメソッドである必要はないですね．
`Initialize`メソッドでは先ほど保存した環境変数を取得して，`config.json`を`*specs.Spec`にマッピングして`Initializer`型のインスタンスを作成して`Initializer.Init`メソッドを呼び出すという具合です．

#### Initializer型

`Initializer`型は以下の様になっています．

```go
type Initializer struct {
	Id           string
	FifoFd       int
	Spec         *specs.Spec
	Cgroups      *cgroups.Cgroups
	Capabilities *capabilities.Capabilities
}
```

`Cgroup`型や`Capabilities`型については後述します．

#### Initializer.Initメソッド

このメソッドがコンテナ作成のコアとなるメソッドで問題の処理を行います．
順を追って処理をみていきます．
`Init`メソッドで行っているのは以下の様な処理です．

- `prepareRootfs`(root file systemの準備)
  - コンテナのroot filesystemをbindマウント
  - `config.json`で指定されているデバイス周りをマウント(**問題が起きている箇所**)
  - `cgroup`でハードウェアリソースを制限
  - `pivot_root`
- capabilityのセット
- `start`サブコマンドからの合図を待ち受ける
- コンテナをスタート

という具合で処理が行われます．

#### rootfsのbindマウント

バインドマウントを行うことで，コンテナのルートファイルシステムを`bundle/rootfs`にします．

```go
func (i *Initializer) prepareRoot() error {
	// mount
	if err := unix.Mount("", "/", "", unix.MS_SLAVE|unix.MS_REC, ""); err != nil {
		return err
	}
	return unix.Mount(i.Spec.Root.Path, i.Spec.Root.Path, "bind", unix.MS_BIND|unix.MS_REC, "")
}
```

#### config.jsonで指定されているデバイスをマウントする

次は`config.json`で指定されているデバイスをマウントします．ここで問題が発生しました．
デフォルトの`config.json`で指定されているデバイスは以下の様になっています．

```json
"mounts": [
		{
			"destination": "/proc",
			"type": "proc",
			"source": "proc"
		},
		{
			"destination": "/dev/shm",
			"type": "tmpfs",
			"source": "shm",
			"options": [
				// ...
			]
		},
		{
			"destination": "/dev/mqueue",
			"type": "mqueue",
			"source": "mqueue",
			"options": [
				// ...
			]
		},
		{
			"destination": "/dev/pts",
			"type": "devpts",
			"source": "devpts",
			"options": [
				// ...
			]
		},
		{
			"destination": "/dev",
			"type": "tmpfs",
			"source": "tmpfs",
			"options": [
				// ...
			]
		},
		{
			"destination": "/sys",
			"type": "sysfs",
			"source": "sysfs",
			"options": [
				// ...
			]
		},
		{
			"destination": "/sys/fs/cgroup",
			"type": "cgroup",
			"source": "cgroup",
			"options": [
				// ...
			]
		}
	],
```

マウントするデバイスのスライスを`*specs.Spec.Mounts`から取り出して`unix.Mount`メソッドで逐一マウントしていく感じです．
コードがこちら．(デバッグ出力などの不要なものを削っています．)
後述しますが，この部分で問題が発生しています．

```go
func Mount(root *specs.Root, mounts []specs.Mount) error {
	wd, err := os.Getwd()
	if err != nil {
		return err
	}
	rootfsPath := root.Path
	if !filepath.IsAbs(rootfsPath) {
		rootfsPath = filepath.Join(wd, rootfsPath)
	}
	for _, m := range mounts {
		target := filepath.Join(rootfsPath, m.Destination)
		if _, err := os.Stat(target); err != nil {
			if err := os.MkdirAll(target, 0755); err != nil {
				return err
			}
		}
		flags, _, data, _ := parseMountOptions(m.Options)
		if err := unix.Mount(m.Source, target, m.Type, uintptr(flags), data); err != nil {
			logrus.Debug(err)
			return err
		}
	}
	return nil
}
```

この様にしてスライスから取り出した各要素に対してマウントを繰り返す様にしています．基本的にruncのコードもその様になっていました．

#### cgroup

`cgroup`に関しても，`config.json`で指定された値をセットするという感じです．
一例がこちら．

```go
func (cg *Cgroups) limitCpu() error {
	if cg.Resources == nil || cg.Resources.CPU == nil {
		logrus.Debugf("cpu limitation is not set")
		return nil
	}
	dir := filepath.Join(cg.Root, "cpu", "mycon")
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	if cg.Resources.CPU.Shares != nil {
		if err := writeFile(dir, cpuShares, strconv.FormatUint(*cg.Resources.CPU.Shares, 10)); err != nil {
			return err
		}
	}
	// ...
}
```

この場合だと，`/sys/fs/cgroup/cpu/mycon/cpu.shares`に値を書き込むことでセットしています．

#### pivot_root

最後に`pivot_root`を行って，コンテナプロセスのルートファイルシステムを隔離します．
`chroot`と`pivot_root`の違いに関しては[こちら](https://employment.en-japan.com/engineerhub/entry/2019/02/05/103000#chroot%E3%81%A8pivot_root)を参照してください．
pivot_rootを実際に行うコードがこちら．

```go
func (i *Initializer) pivotRoot() error {
	oldroot, err := unix.Open("/", unix.O_DIRECTORY|unix.O_RDONLY, 0)
	if err != nil {
		logrus.Debugf("failed to open old root")
		return err
	}
	defer unix.Close(oldroot)
	newroot, err := unix.Open(i.Spec.Root.Path, unix.O_DIRECTORY|unix.O_RDONLY, 0)
	if err != nil {
		logrus.Debug("failed to open new root: ", i.Spec.Root.Path)
		cd, _ := os.Getwd()
		logrus.Debug("now in ", cd)
		return err
	}
	defer unix.Close(newroot)
	// fetch new root file system
	if err := unix.Fchdir(newroot); err != nil {
		logrus.Debug("failed to fetch new root")
		return err
	}
	if err := unix.PivotRoot(".", "."); err != nil {
		logrus.Debugf("failed to pivot_root: %v", err)
		return err
	}
	if err := unix.Fchdir(oldroot); err != nil {
		logrus.Debug("failed to fetch old root")
		return err
	}
	if err := unix.Mount("", ".", "", unix.MS_SLAVE|unix.MS_REC, ""); err != nil {
		logrus.Debug("failed to mount .")
		return err
	}
	if err := unix.Unmount(".", unix.MNT_DETACH); err != nil {
		logrus.Debug("failed to unmount .")
		return err
	}
	if err := unix.Chdir("/"); err != nil {
		logrus.Debug("failed to chdir /")
		return fmt.Errorf("failed to chdir: %v", err)
	}
	return nil
}
```

まず，`oldroot`に現在のファイルシステムのrootを開いたfdを保存，また，`newroot`に新しいファイルシステムのルートとなるポイントを開いたfdを保存します．
その後，newrootに移動して`pivot_root`を行います．

pivot_rootが行えるにはいくつか条件があります．[こちら](https://tenforward.hatenablog.com/entry/2017/06/28/021019)を参照してください．
pivot_rootに関してはまだ僕も理解が浅いのでLinuxのファイルシステムなどについてもっと勉強する必要がありそうです．

#### capability

capabilitiesのセットには[syndtr/gocapability/capability](https://github.com/syndtr/gocapability/tree/master/capability)を使用しています．
`config.json`に設定されたcapabilitiesを次の構造体にマッピングしています．

```go
type Capabilities struct {
	CapMap      map[string]capability.Cap
	Pid         capability.Capabilities
	Bounding    []capability.Cap
	Inheritable []capability.Cap
	Effective   []capability.Cap
	Permitted   []capability.Cap
	Ambient     []capability.Cap
}
```

#### startを待ち受ける

リソースの分離などが完了したあと，スタートするためにシグナルを待ち受けます．

```go
if err := <- i.waitToStart(); err != nil {
		logrus.Debug("failed to wait to start: ", err)
		return err
	}
```

`waitToStart`では`/proc/self/fd/%d`で環境変数に渡されたファイルディスクリプタの値でファイルを開きます．


スタートの合図があった場合，セットされていたコマンドを実行します．

### 実装まとめ

以上がこれまで僕が実装した部分になります．とりあえずプロセス起動，cgroup, capabiltiesと段階を踏んで実装してきました．ここら辺はコミットを辿ってみてください．
また，上述したマウントできない問題によりプロセス間でシグナルを送受信することができず，createコマンドを実行すると`waitToStart`でエラーを吐くため`waitToStart`の部分をコメントアウトしてそのままプロセスを起動している状態です．
また，プロセスを起動しても`/dev/pts`がマウントできていないせいか，入力を受け付けてくれず，すぐにプロセスからログアウトするという状況になってます．

## まとめ

今回は自作コンテナに挑戦しましたが，エラーを解決できず，いったん断念してLinuxやその他の知識をもっとつけてから続きをしようかなと思っています．
なかなかうまくいきませんね．

## 参考

- [https://github.com/rrreeeyyy/container-internship](https://github.com/rrreeeyyy/container-internship)
- [dup man](https://kazmax.zpp.jp/cmd/d/dup.2.html)
- [コンテナ仮想、その裏側 〜user namespaceとrootlessコンテナ〜](https://tech.retrieva.jp/entry/2019/06/04/130134)
- [LXCで学ぶコンテナ入門 －軽量仮想化環境を実現する技術](https://gihyo.jp/admin/serial/01/linux_containers/0003)
- [コンテナユーザなら誰もが使っているランタイム「runc」を俯瞰する[Container Runtime Meetup #1発表レポート]](https://medium.com/nttlabs/runc-overview-263b83164c98)
- [runcのcreateコマンドを読む｡](https://drumato.hatenablog.com/entry/2019/03/31/070000)
- [コンテナ技術入門 - 仮想化との違いを知り、要素技術を触って学ぼう](https://employment.en-japan.com/engineerhub/entry/2019/02/05/103000#chroot%E3%81%A8pivot_root)
- [runc](https://github.com/opencontainers/runc)
- [Write Container Runtime in Go](https://speakerdeck.com/tomocy/write-container-runtime-in-go)

### OCI runtime specification

- [https://udzura.hatenablog.jp/entry/2016/08/02/155913](https://udzura.hatenablog.jp/entry/2016/08/02/155913)
- [https://github.com/opencontainers/runtime-spec](https://github.com/opencontainers/runtime-spec)
