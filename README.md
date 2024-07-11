# Custom Nethack server for your friends

I wanted to play Nethack with some friends / colleagues (sharing bones file)
and jails/chroots with Dgamelaunch seemed like an overkill.

So this is a simple script (and sauce) for managing several "virtual accounts"
for multiple people, all running under one unprivileged user, completely
stand-alone.

The only security is the honor system - there are no passwords (hence
"friends"), only usernames. If your friends are nasty, append something
pseudo-random at the end of your username to obfuscate it.


## Build NetHack

Unfortunately, the game has hardcoded absolute paths on several places of its
source code - hardcoded at build time (!!!). That's why you can't just use
nethack provided by your distro - it's hardwired to use `/usr/games` and
`/var/games`.

Fortunately, the build process is pretty easy and can be done unprivileged,
ie. under the same user you plan to run nethack as.

1. Add a new unix user and change shell to it
   ```
   useradd -m nethack
   su - nethack
   ```
2. Get the source and extract it.
```
curl -L -o NetHack-NetHack-3.6.tar.gz \
    https://github.com/NetHack/NetHack/archive/refs/heads/NetHack-3.6.tar.gz
tar xvzf NetHack-NetHack-3.6.tar.gz
cd NetHack-NetHack-3.6
```
3. Configure it with defaults for Linux - this is basically an extract of
   `sys/unix/NewInstall.unx` (install documentation). Also, see `hints/linux`
   (it's a text file) for any details you might want to change, ie. install
   directory. Remember - it has to be hardcoded at build time.
```
cd sys/unix
sh setup.sh hints/linux
cd ../..
```
4. Build the source - you will probably need to repeat this several times as you
   discover missing dependencies (`make`, compiler, `ncurses-devel`, `yacc`,
   etc). Continue only once you managed to build the source without an error.
```
make all
```
5. Install the binaries.
```
make install
```

## Set up nethack-friends

1. Get the contents of this repo into the `nethack` user homedir
```
cd
curl -L -o nethack-friends-main.tar.gz \
    https://github.com/comps/nethack-friends/archive/refs/heads/main.tar.gz
tar --strip-components=1 -xvzf nethack-friends-main.tar.gz
```
2. (Optional) Edit configuration
   - in `run_nethack.sh` (some constants on the top)
   - in `nethackrc.skel` (`.nethackrc` template for all new users)
3. Build helper binaries
```
make -C bin
```

## Configure sshd

1. As root, add this at the end of `/etc/ssh/sshd_config`, assuming your
   unprivileged user is `nethack`:
```
Match User nethack
	DisableForwarding yes
	PermitEmptyPasswords yes
	MaxSessions 1
	PermitUserRC no
	ForceCommand /bin/bash --noprofile --norc /home/nethack/run_nethack.sh
```
2. Restart sshd.
```
systemctl restart sshd
```
3. Prevent TTY login into `nethack` - just in case somebody accesses the
   physical (or serial) console of your system.
```
echo 'exit 0' > /home/nethack/.profile
```
4. Disable password for the `nethack` user, allowing password-less login.
   Don't do this if your server is public-facing - instead, set some password
   known to all your friends, or (better yet) use SSH keys.
```
passwd -d nethack
```

That should be all!

Note that you won't be able to "log into" the `nethack` user after adding the
`exit 0` to `.profile`, however you can use non-login shells to do work under
the `nethack` user, ie.
```
su nethack   # without the dash
```
or via `sudo`:
```
sudo -u nethack bash
```

---

# Compatibility

Currently tested only with NetHack 3.6.

Also, the GNU Linker is required due to `LD_PRELOAD` - this should not be
an issue for 99.9% of you, but for the 0.01% - sorry. You'll have to figure
out how to inject the `fake_uid.c` functions during nethack binary linking.

# Missing features

There's currently no support for delivering mail, but I'd like to implement
that somehow in the future (as lightweight as possible).
