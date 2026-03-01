# build, teardown
- nuke: incus delete --force mike-sandbox 
- launch: incus launch images:ubuntu/24.04/cloud mike-sandbox -p default -p macvlan -p docker \
    --config=cloud-init.user-data="$(cat cc-sandbox-ud.yml)"
- shell: incus exec mike-sandbox bash

# notes to self
- smb is annoyingly unstable on MacOS
- nfs is a pain to set up. best to play uid/guid sync games
- best to make dev user in sandbox uid 504 to match first user on mac tweak as needed
- best to make dev user group in sandbox gid 80 to match mac admin group
- and the sudo usermod -aG dialout $dev_user to allow mac created files with gid 20 from mac staff group
- cant export nfs share from container have to do it from host
- track down host path to container root fs and share home dir from there
  - apt install nfs-kernel-server
  - edit /etc/exports
    - # NFS homedir export for mike-sandbox /home/mike
    - /var/lib/incus/containers/mike-sandbox/rootfs/home/mike *(rw,sync,no_subtree_check)
  - sudo exportfs -ra
  - sudo systemctl restart nfs-server
- mac mount notes
  - edit /etc/fstab
    - k8s-alpha.local:/var/lib/incus/containers/mike-sandbox/rootfs/home/mike  /Users/mike/mnt/sandbox    nfs    resvport,rw    0  0
  - sudo mount -t nfs -o resvport,rw k8s-alpha.local:/var/lib/incus/containers/mike-sandbox/rootfs/home/mike ~/mnt/sandbox

