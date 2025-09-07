+++
categories = [ "tech", "survey" ]
tags = [ "container", "runc", "OCI-runtime", "golang" ]
date = 2020-04-29
title = "runcを使ってみる"
description = "コンテナランタイムのデファクトスタンダードであるruncについて調査します．"
+++

こんにちは．前回のポストからだいぶ時間が空きましたが，相変わらず緊急事態宣言中で自宅待機なので時間を持て余しています．
ONE PIECEを読み返していたんですが，無料で読める分を読み終わってしまったので暇です．
今回はdockerに使用されているコンテナランタイムである`runc`を使ってみました．
では，いきます．

<!--more-->

# runcを使ってみる

## runcとは
`runc`とは，dockerなどのバックエンドで使用されるコンテナランタイムの一つで，dockerのデフォルトのランタイムです．
コンテナプロセスの作成やリソースの制限を実行します．
実装はgolangです．

## 使ってみる
早速使ってみましょう．実験環境にはVagrantで作成したubuntuを使用します．
dockerが動く環境であればruncは入っているはずなのでインストールなどは省略します．

### 概要

>   runc - Open Container Initiative runtime
runc is a command line client for running applications packaged according to
the Open Container Initiative (OCI) format and is a compliant implementation of the
Open Container Initiative specification.

>runc integrates well with existing process supervisors to provide a production
container runtime environment for applications. It can be used with your
existing process monitoring tools and the container will be spawned as a
direct child of the process supervisor.

>Containers are configured using bundles. A bundle for a container is a directory
that includes a specification file named "config.json" and a root filesystem.
The root filesystem contains the contents of the container.

>To start a new instance of a container:
    # runc run [ -b bundle ] <container-id>

>Where "<container-id>" is your name for the instance of the container that you
are starting. The name you provide for the container instance must be unique on
your host. Providing the bundle directory using "-b" is optional. The default
value for "bundle" is the current directory.

使用しそうなコマンドは以下の通り
- create
- delete
- exec
- kill
- ps
- run
- spec
- start

では早速使ってみましょう．

### rootfsの準備
runcでは，dockerと違い作成するコンテナのファイルなどを用意してくれません．そこをいい感じにやってくれているのがdockerということですね．
というわけで自分で用意します．
```
$ mkdir runc-test
$ cd runc-test
```
`rootfs`ディレクトリを作成します．
```
$ mkdir rootfs
```
今回は作成するコンテナのファイルたちをdockerを経由してエクスポートしてきます．
そのために，一旦dockerでコンテナを起動します．今回はcentosイメージを使用しました．(なんでもいいです)
```
$ sudo docker run -it centos /bin/sh
```
別ターミナルで
```
$ sudo docker ps
CONTAINER ID        IMAGE               COMMAND             CREATED             STATUS              PORTS               NAMES
bc36fee690d6        centos              "/bin/sh"           6 seconds ago       Up 5 seconds                            suspicious_keller
```
`NAMES`を記録して，以下コマンドを実行してcentosのファイルシステムをtarファイルにexportします．
```
$ sudo docker export suspicious_keller > runc-test-centos.tar
```
すると，`runc-test-centos.tar`なるファイルが作成されるので展開しましょう．
```
$ tar -xvf runc-test-centos.tar
$ rm runc-test-centos.tar
```
とするとcentosのファイルシステムがカントディレクトリ(/runc-test/rootfs)に展開されます.
```
$ ls
bin  dev  etc  home  lib  lib64  lost+found  media  mnt  opt  proc  root  run  sbin  srv  sys  tmp  usr  var
```
これでrootfsの準備が完了しました．

### config.jsonの準備
コンテナは`config.json`から設定を読み込んで起動されます．ですので，`config.json`を準備しましょう．
`config.json`は`runc spec`コマンドで生成されます．
```
$ cd ..
$ sudo runc spec
```
生成された`config.json`をみてみましょう．
```json
{
	"ociVersion": "1.0.1-dev",
	"process": {
		"terminal": true,
		"user": {
			"uid": 0,
			"gid": 0
		},
		"args": [
			"sh"
		],
		"env": [
			"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
			"TERM=xterm"
		],
		"cwd": "/",
		"capabilities": {
			"bounding": [
				"CAP_AUDIT_WRITE",
				"CAP_KILL",
				"CAP_NET_BIND_SERVICE"
			],
			"effective": [
				"CAP_AUDIT_WRITE",
				"CAP_KILL",
				"CAP_NET_BIND_SERVICE"
			],
			"inheritable": [
				"CAP_AUDIT_WRITE",
				"CAP_KILL",
				"CAP_NET_BIND_SERVICE"
			],
			"permitted": [
				"CAP_AUDIT_WRITE",
				"CAP_KILL",
				"CAP_NET_BIND_SERVICE"
			],
			"ambient": [
				"CAP_AUDIT_WRITE",
				"CAP_KILL",
				"CAP_NET_BIND_SERVICE"
			]
		},
		"rlimits": [
			{
				"type": "RLIMIT_NOFILE",
				"hard": 1024,
				"soft": 1024
			}
		],
		"noNewPrivileges": true
	},
	"root": {
		"path": "rootfs",
		"readonly": true
	},
	"hostname": "runc",
	"mounts": [
		{
			"destination": "/proc",
			"type": "proc",
			"source": "proc"
		},
		{
			"destination": "/dev",
			"type": "tmpfs",
			"source": "tmpfs",
			"options": [
				"nosuid",
				"strictatime",
				"mode=755",
				"size=65536k"
			]
		},
		{
			"destination": "/dev/pts",
			"type": "devpts",
			"source": "devpts",
			"options": [
				"nosuid",
				"noexec",
				"newinstance",
				"ptmxmode=0666",
				"mode=0620",
				"gid=5"
			]
		},
		{
			"destination": "/dev/shm",
			"type": "tmpfs",
			"source": "shm",
			"options": [
				"nosuid",
				"noexec",
				"nodev",
				"mode=1777",
				"size=65536k"
			]
		},
		{
			"destination": "/dev/mqueue",
			"type": "mqueue",
			"source": "mqueue",
			"options": [
				"nosuid",
				"noexec",
				"nodev"
			]
		},
		{
			"destination": "/sys",
			"type": "sysfs",
			"source": "sysfs",
			"options": [
				"nosuid",
				"noexec",
				"nodev",
				"ro"
			]
		},
		{
			"destination": "/sys/fs/cgroup",
			"type": "cgroup",
			"source": "cgroup",
			"options": [
				"nosuid",
				"noexec",
				"nodev",
				"relatime",
				"ro"
			]
		}
	],
	"linux": {
		"resources": {
			"devices": [
				{
					"allow": false,
					"access": "rwm"
				}
			]
		},
		"namespaces": [
			{
				"type": "pid"
			},
			{
				"type": "network"
			},
			{
				"type": "ipc"
			},
			{
				"type": "uts"
			},
			{
				"type": "mount"
			}
		],
		"maskedPaths": [
			"/proc/kcore",
			"/proc/latency_stats",
			"/proc/timer_list",
			"/proc/timer_stats",
			"/proc/sched_debug",
			"/sys/firmware",
			"/proc/scsi"
		],
		"readonlyPaths": [
			"/proc/asound",
			"/proc/bus",
			"/proc/fs",
			"/proc/irq",
			"/proc/sys",
			"/proc/sysrq-trigger"
		]
	}
}
```
`capabilities`や`namespaces`などいろいろ設定されています．
> process -> args

に起動コマンドとして`sh`が登録されているのでコンテナプロセスが`sh`を実行して起動するようです．

### コンテナの起動
それではコンテナプロセスを起動してみます．
コンテナを起動するには`runc run [container-id]`です．
```
$ sudo runc run runc-test-centos
sh-4.4#
```
シェルが立ち上がり，無事起動できているようです．
これでruncでコンテナを起動することができました．

### その他のコマンドを使ってみる
この調子で他のコマンドを使用してみます．
#### create
`create`はコンテナを作成サブコマンドです．
```
$ sudo runc create runc-test-centos2
cannot allocate tty if runc will detach without setting console socket
```
単純に実行するとエラーになりました．
デタッチするときに`console-socket`を設定してないと`tty`を割り当てることができないと言われているので，とりあえず`config.json`の`process>terminal`を`false`に更新して再度実行すると作成できました．

#### list
`list`で作成されたコンテナを確認することができます．
```
$ sudo runc list
ID                  PID         STATUS      BUNDLE                    CREATED                          OWNER
runc-test-centos2   3609        created     /home/vagrant/runc-test   2020-04-29T09:35:09.882689575Z   root
```
無事作成できているようです．

### ps
`ps`で指定したコンテナの状態をみることができます．
先ほど作成した`runc-test-centos2`の状態をみてみましょう．
```$ sudo runc ps runc-test-centos2
UID        PID  PPID  C STIME TTY          TIME CMD
root      3609     1  0 09:35 ?        00:00:00 runc init
```
このコンテナはまだスタートしていないので`CMD`の項目が`runc init`となっていますね．

### start
では，先ほど作成したコンテナを起動してみましょう．
`start`でコンテナを起動します．
```
$ sudo runc start runc-test-centos2
sh: cannot set terminal process group (-1): Inappropriate ioctl for device
sh: no job control in this shell
sh-4.4# vagrant@ubuntu-xenial:~/runc-test$
```
起動しているようですが，シェルのエラーが出ています．
これはおそらく`create`するときに`terminal: false`にしたからですね．別の方法がありそうです．
とりあえず起動はできたのでよしとします．(怠慢)

### delete
`delete`で作成したコンテナを削除します．
```
$ sudo runc delete runc-test-centos2
```
何も出てこなければ正常に削除できています．


## まとめ
今回はコンテナランタイムのデファクトスタンダードである`runc`について一通り使用してみました．dockerでも使用されているのでdockerでコンテナを使用する際に内部でどんなことをしているのかが少し理解できました．


## 参考
- [runCをひと通り使ってみた](https://fstn.hateblo.jp/entry/2015/08/01/231302)
- [github](https://github.com/opencontainers/runc)
- [runc man](https://github.com/opencontainers/runc/tree/master/man)

<disqus />
