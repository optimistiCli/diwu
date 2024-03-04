# Docker Image With Users
Docker build wrapper that:
1. creates timestamped images so that you can quickly roll back to a previous build;
1. cooks a guest-side script allowing to replicate in the guest OS users from a host-side group;
1. fills in config- and script-file templates;
2. helps remove stale images

## Basic operation
The `voorbeeld` subdir contains a working example, I will use it to describe the basic operation of this script, or rather scripts. It builds and runs vim in a docker container – pretty useless as such, but works for a guinea pig.

### Directory structure
```
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
```
* Root dir of the project should be named after the image name, `voorbeeld` (Dutch for 'example') in this case.
* The docker file should be in the root of the project dir and should preferably be named also after the image: `voorbeeld.dockerfile`.
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

## Limitations
1. Only tested on Linux hosts with Linux guests
1. Relies on GNU versions of POSIX utils
2. Template substitution is a bit of amess
3. Running script `scripts/host/<image name>.sh` debug-mounting option `-m` recognizes only:
   * single file COPYs from `config` or `scripts` dirs to full paths
   * eponymous dockerfiles `<image name>.dockerfile`