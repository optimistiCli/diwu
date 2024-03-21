# diwu: Docker Image With Users
A handy wrapper script for building standalone docker images, primarily interactive ones. Originally developed to run dockerized command line applications on a Linux system with no package manager to speak of.

## Main Features
1. Helps replicate host OS users in the guest OS preserving the UIDs.
2. Creates timestamped docker images so that you can quickly switch to a previous build …
3. … and then helps manage stale images.
4. Processes generic templates into guest-side scripts and/or config files.

## Installation
Just copy the script to some dir on the `$PATH`:
```bash
sudo cp -iv diwu.sh /usr/local/bin/
```

## Prerequisites And Limitations
1. Only Linux hosts and guests are currently supported
   * running on macOS hosts is probably feasible, but not yet tested.
2. Diwu relies on GNU basic utils:
   * bash v.4+ 
     * macOS's v.3 would probably do but testing is needed
   * coreutils
   * find
   * sed
3. You should be allowed to run docker on your system. This typically boils down to:
   * your account should be a member of the `docker` group
   * `/var/run/docker.sock` should be assigned to this very group

This is a rather low bar to clear but I still included a crude little script to check:
```bash
$ ./prereq.sh 
Looking good
```

## Basic operation
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
The `voorbeeld` (Dutch for “example”) dir of this repo exhibits the structure that is recommended for a diwu project.

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
The name of the project root dir sets the name of the project. Docker image name, a bunch of project files' names, container name and hostname all derive from it. It is possible to override this name via `-i` option, but generally, it makes sense to go with the project name as the root dir name.
### Docker File
The recommended naming scheme for the docker file is `<project name>.dockerfile`. As it was shown above the traditional `Dockerfile` also works, but such an “impersonal” name can lead to unnecessary confusion. The `-f` option will help if you need to go with some other name for the docker file. 
### Scripts Dir
All project scripts and script templates (see below) are supposed to reside in the `scripts` dir. There are 3 distinct kinds of scripts recognized by diwu.
#### Host Scripts
Host-side scripts in `scripts/host`; the `voorbeeld` project has only one file here: a script for running the project's container, see more on it further.
#### Guest Scripts
Client-side scripts and templates in `scripts/guest` are meant to be copied to the container by the docker file; the `entrypoint.sh` included with this project only serves to demonstrate diwu's operation: generally speaking, a shell script makes a lousy container entry point.
#### Addusers Template
Addusers script template is to be named `addusers.template.sh` and put in the `scripts` dir. As demonstrated above, diwu will also find it in the project's root, but for the sake of general tardiness it's better positioned in the `scripts` dir. The `-a` option allows to use any other file for addusers template and the `-A` stops diwu from searching for it altogether, effectively suppressing the *“No addusers script template found”* warning.
### Config Dir
Any config files and templates thereof to be copied into the image go to the `config` dir. It is sometimes tricky to distinguish files belonging here from the ones that should go to the `scripts/guest` dir, but no matter: diwu treats those two dirs without prejudice.
### Default Vars File
Unless instructed otherwise, diwu looks for templates vars file named `<project name>.vars.ini` in the project root dir. More on templates and vars file(s) further on.
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
## Processing templates
Diwu can process templates into guest-side scripts and config files. Templates are files in `config` and `scripts/guest` dirs named like `<name>.template.<ext>`.

To enable template processing diwu needs a vars file. By default, a file named `<project name>.vars.ini` is looked for in the project root dir. In practice more often than not a vars file is supplied via the `-e` option. If no vars file is found diwu produces a *“No variables file found …”* warning and does not process any templates.

If you do not need template processing just use the `-E` option. It also removes the warning.

Vars files consist of `<var> = <value>` lines. Variable names must follow the usual variable naming convention. Values can not span lines. Any line that does not conform to this format is ignored.
```ini
# Switch to previous tab
TABPREV = F1

# Switch to next tab
TABNEXT = F2
```

Template file should have the variables in “double-mustaches”. Any unset variables are left as is. Here is for example a template for `.vimrc`:
```vim
:set pastetoggle=<f5>
:set tabstop=4 softtabstop=0 expandtab shiftwidth=4 smarttab
:syntax on
:nnoremap <{{TABNEXT}}> :tabnext<CR>
:nnoremap <{{TABPREV}}> :tabprevious<CR>
:tab all
```

Each processed template is written to a file in the temp dir that has the same name but without the `template` “infix”. So `vim.template.rc` becomes `vim.rc`. The path to the temp dir is passed to the docker file as the `DIWU_DIR` argument. Then the docker file should take care of copying it to the right path on the guest.
```Dockerfile
ARG DIWU_DIR
COPY $DIWU_DIR/vim.rc /etc/vim/vimrc.local
```
### Templates And Tags
Sometimes it makes sense to have image tags named after custom vars files. This helps manage several configurations of the same image. Let's say your image needs to connect to one of several servers. If you create a vars file for each server then all the images can be built in one go.
```bash
$ ls -1 *.vars.ini
local.vars.ini
remote.vars.ini

$ for V in *.vars.ini; do diwu.sh -e "$V" -t "${V%.vars.ini}"; done

$ docker image ls pjkt
REPOSITORY   TAG                   IMAGE ID       CREATED            SIZE
pjkt         2024.03.18.18.40.11   e5a4ff5619f0   5 minutes ago      176MB
pjkt         local                 e5a4ff5619f0   5 minutes ago      176MB
pjkt         2024.03.18.18.42.49   f26012ae47b1   2 minutes ago      176MB
pjkt         remote                f26012ae47b1   2 minutes ago      176MB
``` 
## Timestamps And Management
### Image Tagging
Every time diwu builds an image it is assigned a timestamp tag like `2024.12.31.23.59.59`. Also, the newly built image is by default assigned the `latest` tag. Thus the newest version of the image is always the default one in docker terms. The `-t` option allows assigning the image an arbitrary tag and `-T` instructs diwu to leave the image with only a timestamp tag.
### Old Images
This manner of image tagging often leaves you with a lot of old stale timestemp-tagged images. Diwu helps manage them with the `-L` option which prints out all the images that have only timestamp tags, i.e. are not known to be of any particular use. Feeding its output to `docker` allows removing all stale images with one command.
```bash
$ diwu.sh -L
voorbeeld:2024.03.05.09.57.16
voorbeeld:2024.03.03.13.51.18
voorbeeld:2024.03.02.12.46.16

$ docker image rm $(diwu.sh -L)
Untagged: voorbeeld:2024.03.05.09.57.16
Deleted: # yada yada yada
Untagged: voorbeeld:2024.03.03.13.51.18
Deleted: # yada yada yada
Untagged: voorbeeld:2024.03.02.12.46.16
Deleted: # yada yada yada
```
### Temp Dirs
Every time diwu attempts to build an image it creates a temp dir named `.diwu_<project name>_<timestamp>_<random>` in the project root dir. If building fails this temp dir is left behind so they need to be manually deleted.
```bash
$ ls -1d .diwu_*
.diwu_voorbeeld_2024_03_04_15_04_04_MjzV53
.diwu_voorbeeld_2024_03_06_12_04_34_zIYILq

$ rm -rf .diwu_*
```
## Running Images
The images built with diwu are just like any other docker images so they can be run by `docker run` or any wrapper thereof. But since it is mostly targeted at building containerized command line apps it often makes sense to write a project-specific launcher script. The `voorbeeld` project included with this repo comes with a portable and rather generic launcher that can be found in `scripts/host/voorbeeld.sh`. It has some options helpful both for regular use and for debugging images:
* running in a new `screen` window
* daemonizing and optionally following the log
* running a shell as root or as the current user
* mounting files copied to the image by the docker file 
  * this option currently doesn't work with templates and requires the individual `COPY` directives in the docker file with concrete targets
```bash
$ ./voorbeeld/scripts/host/voorbeeld.sh -h
Usage:
  voorbeeld.sh [-h] [-s] [-S | -R] [-t <tag>] [-w] [-m] [-d | -D [-l]]
               [-e | -E | -k]

Run voorbeeld.

Options:
  -h Print help and exit
  -s Simmulate, just print out commands
  -S Run shell
  -R Run shell with root inside
  -t Another tag instaed of 'latest'
  -w Open new screen window
  -m Mount copied files for debugging
  -d Daemonize
  -l Follow container log
  -e Run docker exec
  -E Run docker exec with root inside
  -k Kill container
```
Feel free to use this script as a starting point for your project-specific launchers.
## TODO
* Add docker file templates for automating the copying of files generated from templates.
  * Guess shell from shebang
  * Put files in `/opt/diwu`
* Add “skeleton” project generation
* Add `addgroup.template.sh`
* Add some form of automation for vars files to image tags coordination 
* Remove temp dir after a failed build
* Improve debug-mounting in launcher
* Adapt to run on macOS host
