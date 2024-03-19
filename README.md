# diwu: Docker Image With Users
A handy wrapper script for building standalone docker images, primarily interactive ones.

## Main Features
1. Helps replicate host OS users in the guest OS with the same UIDs.
2. Creates timestamped docker images so that you can quickly switch to a previous build …
3. … and then helps manage stale images.
4. Processes generic templates into guest-side scripts and/or config files.

## Installation
Just copy the script to some dir on the `$PATH`:
```bash
sudo cp -iv diwu.sh /usr/local/bin/
```

## Prerequisites And Limitations
Only Linux hosts and guests are currently supported. Running on macOS hosts is probably feasible, but not yet tested.

Diwu relies on GNU basic utils:
   * bash v.4+ (macOS's v.3 would probably do but testing is needed)
   * coreutils
   * find
   * sed

## Basic operation
First off I assume that you are allowed to run docker on your system, i.e. your account is a member of the `docker` group and `/var/run/docker.sock` is assigned to this very group:
```bash
$ id -Gn
users docker
$ ls -l /var/run/docker.sock 
srw-rw---- 1 root docker 0 Mar  9 07:16 /var/run/docker.sock
```
Let's say you want to run `vim` in a container. You create a dir for your new project, and inside it, you create a docker file:

```bash
$ tree vimd
vimd
└── Dockerfile

1 directory, 1 file
```
The docker file doesn't do much, just installs `vim` on a current Ubuntu and designates it as the container's entrypoint.
```Dockerfile
FROM ubuntu:rolling

RUN echo Adelante amigos \
    && export \
        DEBIAN_FRONTEND='noninteractive' \
        TZ='Antarctica/Troll' \
    && apt-get -y update \
    && apt-get -y upgrade \
    && apt-get -y dist-upgrade \
    && apt-get install -y --no-install-recommends \
        vim \
    && apt-get -y autoremove \
    && apt-get -y clean \
    && apt-get -y autoclean \
    && rm -rf /var/lib/apt/lists/* \
    && echo Et voila

ENTRYPOINT ["/usr/bin/vim"]
```
To build this image just run diwu in your project dir:
```bash
$ diwu.sh
Warning: No addusers script template found

Warning: No variables file found, extra templates will not be processed

Sending build context to Docker daemon   2.56kB
Step 1/3 : FROM ubuntu:rolling
 ---> 483a94112583
Step 2/3 : RUN echo Adelante amigos     && export         DEBIAN_FRONTEND='noninteractive'         TZ='Antarctica/Troll'     && apt-get -y update     && apt-get -y upgrade     && apt-get -y dist-upgrade     && apt-get install -y --no-install-recommends         vim     && apt-get -y autoremove     && apt-get -y clean     && apt-get -y autoclean     && rm -rf /var/lib/apt/lists/*     && echo Et voila
 ---> Running in 534dbb87357d
Adelante amigos
# yada yada yada
Et voila
Removing intermediate container 534dbb87357d
 ---> fd305516b80c
Step 3/3 : ENTRYPOINT ["/usr/bin/vim"]
 ---> Running in b77953f9968b
Removing intermediate container b77953f9968b
 ---> 18b6ea18a28c
Successfully built 18b6ea18a28c
Successfully tagged vimd:2024.03.15.09.54.51
removed directory '.diwu_vimd_2024_03_15_09_54_51_OdSQA0'
```
The built image is named `vimd` after your project dir. You can specify another name with `-i` option if you like. You have now one image with 2 tags: a timestamp and the `latest` tag:
```bash
$ docker image ls vimd
REPOSITORY   TAG                   IMAGE ID       CREATED          SIZE
vimd         2024.03.15.09.54.51   18b6ea18a28c   18 minutes ago   176MB
vimd         latest                18b6ea18a28c   18 minutes ago   176MB
```
Now you remember that you have a fancy `.vimrc` and decide to add it to the container:
```bash
$ cp -iv ~/.vimrc vim.rc
$ echo 'COPY vim.rc /etc/vim/vimrc.local' >> Dockerfile
```
Run diwu to build it again
```bash
$ diwu.sh 
Warning: No addusers script template found

Warning: No variables file found, extra templates will not be processed

Sending build context to Docker daemon  3.584kB
Step 1/4 : FROM ubuntu:rolling
 ---> 483a94112583
Step 2/4 : RUN echo Adelante amigos     && export         DEBIAN_FRONTEND='noninteractive'         TZ='Antarctica/Troll'     && apt-get -y update     && apt-get -y upgrade     && apt-get -y dist-upgrade     && apt-get install -y --no-install-recommends         vim     && apt-get -y autoremove     && apt-get -y clean     && apt-get -y autoclean     && rm -rf /var/lib/apt/lists/*     && echo Et voila
 ---> Using cache
 ---> fd305516b80c
Step 3/4 : ENTRYPOINT ["/usr/bin/vim"]
 ---> Using cache
 ---> 18b6ea18a28c
Step 4/4 : COPY vim.rc /etc/vim/vimrc.local
 ---> bdde11b7da11
Successfully built bdde11b7da11
Successfully tagged vimd:2024.03.15.10.27.44
removed directory '.diwu_vimd_2024_03_15_10_27_44_8mO2u5'
```
Now you have 2 `vimd` images:
1. the new one, which includes `vimrc`, is tagged with a timestamp and with the `latest` tag
1. the first build, without `vimrc`, has now only the timestamp tag
```bash
$ docker image ls vimd
REPOSITORY   TAG                   IMAGE ID       CREATED             SIZE
vimd         2024.03.15.10.27.44   bdde11b7da11   29 minutes ago      176MB
vimd         latest                bdde11b7da11   29 minutes ago      176MB
vimd         2024.03.15.09.54.51   18b6ea18a28c   About an hour ago   176MB
```
You can test your dockerized `vim` now:
```bash
docker run -it --rm -v "$(pwd)":/mnt --workdir /mnt vimd
```
It works (I hope). Now let's say you want to clean up after yourself and remove the stale first image, the one without `vimrc`. Diwu has an `-L` option that lists all the images of the current name (as guessed from the project dir name, or given by `-i` option) that sport only timestamp tags. It is assumed that any image worth keeping is tagged something meaningful, either by diwu, or manually.
```bash
$ diwu.sh -L
vimd:2024.03.15.09.54.51
```
You can remove all the stale images in one go like this:
```bash
$ docker image rm $(diwu.sh -L)
Untagged: vimd:2024.03.15.09.54.51
```
Now you start using your dockerized vim only to realize that any new file it creates is owned by root – this would not do. To rectify this issue you can just run your container as the current user:
```bash
docker run -it --rm -v "$(pwd)":/mnt --workdir /mnt -u $(id -u):$(id -g) vimd
```
If all you need is a `vim` then this does the trick. But bear in mind: this user has no home dir in the guest OS and even no name:
```bash
$ docker run -it --rm -u $(id -u):$(id -g) --entrypoint /bin/bash vimd
I have no name!@e7f53485960d:/$
```
This invites trouble if you ask me. So let's use diwu to replicate some host-side users.

By default, diwu replicates all users that are members of the `docker` group in the host OS. If there is no `docker` group it tries `administrators`, and if this also fails then it gives up. Alternatively, you could specify another source group via `-g` option.

To activate user replication you need to craete a file named `addusers.template.sh`. This is a template for the guest-side script that adds users while the image is built. You can put this file in the root directory of your project (recommended dir structure and naming conventions are described below). At the time of this writing, the minimum `addusers.template.sh` for Ubuntu guest is as follows:
```bash
useradd -u {{USER_ID}} -g {{USER_GROUP_ID}} -m -c '' -p '' {{USER_NAME}}
```
Next the processing of the addusers script must be added to the `Dockerfile`:
```Dockerfile
FROM ubuntu:rolling

# yada yada yada

ARG ADDUSERS
COPY $ADDUSERS /tmp/addusers.sh
RUN /bin/bash /tmp/addusers.sh
```
You're good to go now but if you are curious about what the resulting addusers script looks like then why don't you run diwu in simulation mode first:
```bash
$ diwu.sh -s
Warning: No variables file found, extra templates will not be processed

>============================ addusers.sh =============================<
useradd -u 1001 -g 100 -m -c '' -p '' superuser

useradd -u 1002 -g 100 -m -c '' -p '' supervisor
>======================================================================<
docker build -f Dockerfile -t vimd:2024.03.15.12.39.08 --build-arg ADDUSERS=.diwu_vimd_2024_03_15_12_39_08_xuNP4C/addusers.sh .
docker tag vimd:2024.03.15.12.39.08 vimd:latest
removed '.diwu_vimd_2024_03_15_12_39_08_xuNP4C/addusers.sh'
removed directory '.diwu_vimd_2024_03_15_12_39_08_xuNP4C'
```
This shows that diwu found 2 users in the `docker` group: `superuser` and `supervisor` with UIDs `1001` and `1002` respectively. Also, you can see that, unless instructed otherwise, diwu assigns GID `100` to all replicated users – read on or just run `diwu -h` to find out how this can be changed.

Now you can run diwu to do what its name suggests it does: build a docker image with users:
```bash
$ diwu.sh
Warning: No variables file found, extra templates will not be processed
  
Sending build context to Docker daemon  6.144kB
Step 1/7 : FROM ubuntu:rolling
 ---> 483a94112583
Step 2/7 : RUN echo Adelante amigos     && export         DEBIAN_FRONTEND='noninteractive'         TZ='Antarctica/Troll'     && apt-get -y update     && apt-get -y upgrade     &&
 apt-get -y dist-upgrade     && apt-get install -y --no-install-recommends         vim     && apt-get -y autoremove     && apt-get -y clean     && apt-get -y autoclean     && rm 
-rf /var/lib/apt/lists/*     && echo Et voila
 ---> Using cache
 ---> fd305516b80c
Step 3/7 : ENTRYPOINT ["/usr/bin/vim"]
 ---> Using cache
 ---> 18b6ea18a28c
Step 4/7 : COPY vim.rc /etc/vim/vimrc.local
 ---> Using cache
 ---> bdde11b7da11
Step 5/7 : ARG ADDUSERS
 ---> Running in 68dd20c0861d
Removing intermediate container 68dd20c0861d
 ---> 79fa7e2177be
Step 6/7 : COPY $ADDUSERS /tmp/addusers.sh
 ---> ceb8a2a457f9
Step 7/7 : RUN /bin/bash /tmp/addusers.sh
 ---> Running in 0a5e42ad9a35
Removing intermediate container 0a5e42ad9a35
 ---> 83bb84cd2882
Successfully built 83bb84cd2882
Successfully tagged vimd:2024.03.15.12.53.27
removed '.diwu_vimd_2024_03_15_12_53_27_62ZqCO/addusers.sh'
removed directory '.diwu_vimd_2024_03_15_12_53_27_62ZqCO'
```
All the files used in this walkthrough can be found in the `vimd` dir in this repo.

## Implied Dir Structure
The `voorbeeld` (Dutch for “example”) dir of this repo exhibits the structure that is recommended for the diwu projects.

```
$ tree voorbeeld
voorbeeld
├── config
│   └── vim.template.rc
├── scripts
│   ├── addusers.template.sh
│   ├── guest
│   │   └── entrypoint.sh
│   └── host
│       └── voorbeeld.sh
├── voorbeeld.dockerfile
└── voorbeeld.vars.ini

5 directories, 6 files

```
### Project Root
The name of the project root dir sets the name for the project. Docker image name, a bunch of project files' names, container name and hostname all derive from it. It is possible to override this name via `-i` option, but generally, it makes sense to go with the project name as the root dir name.
### Docker File
The recommended naming scheme for the docker file is `<project name>.dockerfile`. As it was shown above the traditional `Dockerfile` also works, but such an “impersonal” name can lead to unnecessary confusion. The `-f` option will help if you need to go with some other name for the docker file. 
### Scripts Dir
All project scripts and script templates (see below) are supposed to reside in the `scripts` dir. There are 3 distinct kinds of scripts recognized by diwu.
#### Host Scripts
Host-side scripts in `scripts/host`; the `voorbeeld` project has only one entry here: a script for running the project's container, see more on it further.
#### Guest Scripts
Client-side scripts and templates in `scripts/guest` are meant to be copied to the container by the docker file; the `entrypoint.sh` included with this project only serves to demonstrate diwu's operation: generally speaking, a shell script makes a lousy container entry point.
#### Addusers Template
Addusers script template is to be named `addusers.template.sh` and put in the `scripts` dir. As demonstrated above, diwu will also find it in the project's root, but for the sake of general tardiness it's better positioned in the `scripts` dir. The `-a` option allows to use any other file for addusers template and the `-A` stops diwu from searching for it altogether, effectively suppressing the *“No addusers script template found”* warning.
### Config Dir
Any config files and templates thereof to be copied into the image go to the `config` dir. It is sometimes tricky to distinguish files belonging here from the ones that should go to the `scripts/guest` dir, but no matter: diwu treats those two dirs without prejudice.
### Default Vars File
Unless instructed otherwise, diwu looks for templates vars file named `<project name.vars.ini>` in the project root dir. More on templates and vars file(s) further on.
## Addusers operation
Diwu includes a mechanism for replicating in the guest OS the host-side users from a specific group. By default, it replicates members of `docker` or `administrators` group, otherwise the source host-side group can be set via the `-g` option.

User replication is triggered if the addusers script template file is found. Diwu searches for a file named `addusers.template.sh` in `scripts/users`, `scripts` and project root dir consecutively. Otherwise, a template can be specified via the `-a` option. In the absence of an addusers template, the *“No addusers script template found”* warning is displayed.

To stop diwu from replicating users give it a `-A` option. It also suppresses the abovementioned warning.

The addusers template file is an arbitrary shell script, where 3 “double-mustached” variables get substituted with actual values for every replicated user. Empty and commented lines are omitted.

A basic addusers template for an Alpine guest:
```bash
# Available variables:
# {{USER_NAME}}
# {{USER_ID}}
# {{USER_GROUP_ID}}

adduser -g {{USER_NAME}} -s /bin/sh -D -u {{USER_ID}} {{USER_NAME}} {{USER_GROUP_ID}}
```
The vaiables are:
* `{{USER_NAME}}` - user's name in the host OS
* `{{USER_ID}}` - user's UID in the host OS
* `{{USER_GROUP_ID}}` - guest user's GID, its value depends on the options passed to diwu:
  * `100` is the default GID if no options are given
  * the host-side user's actual GID if `-G user` is set
  * the source host-side group GID if `-G group` is set
  * an arbitrary number if `-G <number>` is set

Diwu creates an actual addusers script in a temp dir and passes the path to this script to the docker file by adding `--build-arg ADDUSERS=<path>` to `docker build`. To see the generated script and docker invocation parameters please run diwu in simulation mode by adding the `-s` option.

To process the generated addusers script while building the image please add something like this to the docker file:
```Dockerfile
ARG ADDUSERS
COPY $ADDUSERS /tmp/addusers.sh
RUN /bin/sh /tmp/addusers.sh
```





---------------------


* The `scripts/adduser.template.sh` is used to generate the guest-side script that is run from the dockerfile and performs the same operations for every replicated user. This particular script just adds users to the guest OS.
* The `scripts/host` is for the host-side scripts. It is imho a good practice to name the script that runs the container after the image. The one that comes with this repo is thus named `voorbeeld.sh`. It actually is  very generic: it can be copied and renamed for other projects and used as-is, or as a starting point for something more project-specific.
* The `scripts/guest` dir contains scripts and script templates used on the guest side. All files named like `<name>.template.<ext>` are considered templates. More on this below.
* The `config` dir is supposed to contain config files and templates of config files. All files named like `<name>.template.<ext>` are considered templates. More on this below.
* The vars file `voorbeeld.vars.ini` is used for filling in all the templates in `config` and `scripts/guest` dirs. More on templates below.





























### Building image
Just run the script in the project dir, it should pick up all the settings.
```bash
cd voorbeeld
../diwu.sh
```

### Debugging images
Actually before building an image, it generally makes sense to run a simulation by passing the `-s` option. All the filled in templates and all docker calls get printed out:
```bash
diwu.sh -s
>============================ addusers.sh =============================<
adduser -g admin -s /bin/sh -D -u 1024 admin 100

adduser -g ish -s /bin/sh -D -u 1028 ish 100

adduser -g supervisor -s /bin/sh -D -u 1026 supervisor 100
>======================================================================<
>=============================== vim.rc ===============================<
:set pastetoggle=<f5>
:set tabstop=4 softtabstop=0 expandtab shiftwidth=4 smarttab
:syntax on
:nnoremap <F2> :tabnext<CR>
:nnoremap <F1> :tabprevious<CR>
:tab all
>======================================================================<
docker build -f voorbeeld.dockerfile -t voorbeeld:2024.03.03.14.13.33 --build-arg ADDUSERS=.diwu_2024.03.03.14.13.33_Uh4Tp9/addusers.sh --build-arg DIWU_DIR=.diwu_2024.03.03.14.13.33_Uh4Tp9 .
removed '.diwu_2024.03.03.14.13.33_Uh4Tp9/vim.rc'
removed '.diwu_2024.03.03.14.13.33_Uh4Tp9/addusers.sh'
removed directory '.diwu_2024.03.03.14.13.33_Uh4Tp9'
docker tag voorbeeld:2024.03.03.14.13.33 voorbeeld:latest
```
NB: shell commands are printed without quotes, don't panic :-)

### Running container
Just run the `scripts/host/voorbeeld.sh` to create and run the container. If you are inside a `screen` session you might want to add the `-w` option to run container in a new screen window. This goes mostly for the interactive images, like this one, with a `vim`.

To daemonize the container use `-d` option of the running script. Stopping it can be done with `-k`. A useful combination of options is `-dwl` that runs container daemonized and immediately launches the log viewer in a new screen window.

### Timestamps and cleaning up
Every time you run the script it creates an image tagged `<image name>:<year>.<month>.<day>.<hour>.<minute>.<second>`. This is handy if you need to run a previous build. The latest build is also tagged `<image name>:latest` so you don't need to follow this temporal tags. Another tag, instead of `latest` can be assigned by using the `-t` option.

Once you don't need the old builds, they can be listed by running `diwu.sh -L`. Or you can remove them all in one go:
```bash
docker image rm $(diwu.sh -L)
```

NB: Images that have **only** temporal tags get listed by `-L` and thus deleted by the command above.

### All available options
* **-h** Print help and exit
* **-s** Simulate, just print out scripts and commands
* **-i** Image name, current dir name used if omitted
* **-f** Docker file, if omitted looks for `<image name>.dockerfile`, `Dockerfile`
* **-g** Name of the selected host-side users group, if omitted tries using `docker`, `administrators`
* **-G** Id of the guest-side primary users group, if omitted uses 100
* **-a** Adduser script template, if omitted looks for `addusers.template.sh` in `scripts/users/`, `scripts/`, `./`
* **-A** Do not generate adduser script
* **-t** Tag image something else instead of `latest`
* **-T** Build time-tagged image only, do NOT tag it as `latest`
* **-e** File defining variables for extra templates, if omitted looks for `<image name>.vars.ini`
* **-L** List images with timed tag only and exit

## Adding users
In some use cases it helps to have in the guest OS inside the container some of the same users and groups that you have in the host OS. I find it is specifically handy with interactive containers when it is hard to plan ahead the access rights to the files and folders.

The `diwu.sh` script resolves this by going through a specific user group on the host and filling in the names, UID's and GID's of all the users in this group into `addusers.template.sh` thus generating an `addusers.sh` script that is run from the dockerfile while building an image.

Before building the image `diwu.sh` creates a temporary directory named `.diwu_<timestamp>_<randomness>` in the project directory. Inside it the `addusers.sh` is created. Then path to it is passed to `docker build` as an argument named `ADDUSERS`. And then dockerfile can execute this script while building the image.

Please see the sources of `addusers.template.sh` and `voorbeeld.dockerfile` for details.

By default, the script takes the list of users from the `docker` group on the host, or from `administrators` group. If neither group is found on the host, then no users are added. Otherwise, a source group name can be passed to the script via the `-g` option.

The same GID `100` is passed to `addusers.template.sh` for all users. Another GID can be specified with the `-G` option. If you want to create a GID for every user in the guest OS, or just leave the GID selection to the OS itself this can be achieved by modifying the `addusers.template.sh`.

## Processing templates
If some settings in the image need to be easily adjusted, or if several versions of an image with different setting should exist at the same time, then it makes sense to create a custom config, or a bunch of configs, for the image and then fill the values during the build.

This script uses vars for this purpose. By default the script looks for the file named `<image name>.vars.ini` in the project root, but it's often more handy to keep elsewhere and pass the path to it via the `-e` option. If no vars file is found, then templates processing doesn't happen.

Actually, the vars file is a proper `bash` script that gets sourced by the `diwu.sh` script. This means that caution must be excersized in terms of the access rights to the vars files.

Templates are all files fitting the `<name>.template.<ext>` naming convention found in `config` and `scripts/guest` dirs. Variable names in templates follow (to an extent) the shell convention: `$VARIABLE_NAME`. Curly brackets are not currently supported. Variables with overlapping names like `$VAR` and `$VAR1` might get confused in substitution. Also, variable names that conflict with host OS environment will be ignored. 

NB: Template variable naming situation will probably be changed / improved further on.

Each template is processed into a file of the same name just without the `template` infix and put into the temp dir mentioned above. If at least one file was generated, then the path to the temp dir is passed to `docker build` via the `DIWU_DIR` argument. Please see the `config/vim.template.rc` and `voorbeeld.dockerfile` for details.