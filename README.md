# Autorice
This repository installs my dotfiles on a fresh install of any arch-based distributions. I used this repo to automatically install my setup across 3 different devices, and try to keep it up to date with any programs or configurations that I use.

## Installation

On an Arch based distribution as root, run the following:

```
curl -LO https://raw.githubusercontent.com/llGaetanll/autorice/master/rice.sh
sh rice.sh
```

## Customization
This script largely comes from [lukesmithxyz/LARBS](https://github.com/lukesmithxyz/LARBS), 
so a lot of functionality is going to remain the same.

The script installs all the packages defined the `progs.csv` file, as well as my dotfiles 
[llGaetanll/rice](https://github.com/llGaetanll/rice).

You can run the script with any of these options to modify what gets installed:
- `-r`: custom dotfiles repository url. Defaults to [llGaetanll/rice](https://github.com/llGaetanll/rice). 
- `-p`: custom programs list/dependencies (local file or URL). Defaults to `progs.csv`.
- `-a`: a custom AUR helper (must be able to install with `-S` unless you
  change the relevant line in the script. Defaults to `yay`.

### The Program list

This script will parse the given programs list and install all given programs. Note
that the programs file must be a three column `.csv`. You can add comments starting with `#`.

The first column is a "tag" that determines how the program is installed:
 - ` ` (Nothing) will use pacman to install the package. You can check if the package is available by running `pacman -Ss <package-name>`
 - `A` will use the given AUR helper (defaults to `yay`) to install the package from the AUR
 - `G` will manually install the git repository with `make && sudo make install`
 - `P` will `pipinstall` the package.

The second column is the name of the program in the repository, or the link to
the git repository, and the third comment is a description (should be a verb
phrase) that describes the program. During installation, the script will print out
this information in a grammatical sentence. It also doubles as documentation
for people who read the csv or who want to install my dotfiles manually.

Depending on your own build, you may want to tactically order the programs in
your programs file. The script will install from the top to the bottom.

If you include commas in your program descriptions, be sure to include double
quotes around the whole description to ensure correct parsing.

### The script itself

The script is extensively divided into functions for easier readability and
trouble-shooting. Most everything should be self-explanatory.

The main work is done by the `installationloop` function, which iterates
through the programs file and determines based on the tag of each program,
which commands to run to install it. You can easily add new methods of
installations and tags as well.

Note that programs from the AUR can only be built by a non-root user. What
the script does to bypass this by default is to temporarily allow the newly created
user to use `sudo` without a password (so the user won't be prompted for a
password multiple times in installation). This is done ad-hocly, but
effectively with the `newperms` function. At the end of installation,
`newperms` removes those settings, giving the user the ability to run only
several basic sudo commands without a password (`shutdown`, `reboot`,
`pacman -Syu`).
