# Luke's Auto-Rice Bootstraping Scripts (LARBS)


## Installation:

On an Arch based distribution as root, run the following:

```
curl -LO larbs.xyz/larbs.sh
sh larbs.sh
```

## Customization

By default, LARBS uses the programs [here in progs.csv](progs.csv) and installs
[my dotfiles repo (voidrice) here](https://github.com/lukesmithxyz/voidrice),
but you can easily change this by either modifying the default variables at the
beginning of the script or giving the script one of these options:

- `-r`: custom dotfiles repository (URL)
- `-p`: custom programs list/dependencies (local file or URL)
- `-a`: a custom AUR helper (must be able to install with `-S` unless you
  change the relevant line in the script

### The `progs.csv` list

LARBS will parse the given programs list and install all given programs. Note
that the programs file must be a three column `.csv`.

The first column is a "tag" that determines how the program is installed:
 - ` ` (Nothing) will use pacman to install the package. You can check if the package is available by running `pacman -Qs <package-name>`
 - `A` will use yay by default, to install the package from the AUR
 - `G` will manually install the git repository with `make && sudo make install`
 - `P` will `pipinstall` the package 

The second column is the name of the program in the repository, or the link to
the git repository, and the third comment is a description (should be a verb
phrase) that describes the program. During installation, LARBS will print out
this information in a grammatical sentence. It also doubles as documentation
for people who read the csv or who want to install my dotfiles manually.

Depending on your own build, you may want to tactically order the programs in
your programs file. LARBS will install from the top to the bottom.

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
LARBS does to bypass this by default is to temporarily allow the newly created
user to use `sudo` without a password (so the user won't be prompted for a
password multiple times in installation). This is done ad-hocly, but
effectively with the `newperms` function. At the end of installation,
`newperms` removes those settings, giving the user the ability to run only
several basic sudo commands without a password (`shutdown`, `reboot`,
`pacman -Syu`).

### TODO
- add polybar to list of installs
- add one wallpaper in local cache when first loading
- add fontconfig
- install font required by powerlevel10k
- add poewrlevel10k profile
- install zsh git repos on init
- `ttf-apple-emoji` not loaded
