# Working on Manatee

When working on Manatee, it's convenient to be able to run multiple instances in
the same environment.  This won't allow you to test all possible failure modes,
but it works for most basic functionality.

This process involves:

* Deploying a zone with the right versions of postgres available and with the
  ability to manage ZFS datasets.  Manatee needs to be able to run as root
  inside this zone.
* Installing postgres, git, gcc, and other tools required to build.
* Creating a ZFS dataset for each Manatee peer you want to run.  (We'll assume
  three instances in this guide.)
* Creating a configuration file for each Manatee peer you want to run.
* Starting each peer by hand.


## Summary

These steps assume you've already got ZooKeeper running somewhere.  In
the steps below, $ZK_CONN_STR is a connection string, or a comma-separated list
of IP:PORT pairs for the zookeeper cluster.  If you're provisioning inside a
non-production Triton installation that you own, it's generally acceptable to
provision your zone onto the admin and external networks and make use of
Triton's `binder` instance.

Run all of the following as root:

1. Provision a SmartOS zone using multiarch 13.3.1.  This is image
   4aec529c-55f9-11e3-868e-a37707fcbe86.  Be sure to provision the zone with a
   delegated ZFS dataset.
1. Log into the zone and run the following steps as root (or with sudo or
   as another privileged user).
1. Install packages:

        # pkgin in git gmake gcc47 bison flex

1. Get and build a local copy of this repo:

        # git clone https://github.com/joyent/manatee
        # cd manatee
        # make

1. Get and build the versions of PostgreSQL that you're interested in (currently
supported are 9.6 and 9.2).
    1. For 9.2:

        # git submodule add https://github.com/postgres/postgres.git \
            deps/postgresql92 && cd deps/postgresql92 && git checkout 73c122 \
            && cd -
        # make -f Makefile.postgres RELSTAGEDIR=/tmp/test \
            DEPSDIR=/root/manatee/deps pg92

    1. For 9.6:

1. Install PostgreSQL versions (note: the PostgreSQL binary directory is a
symlink created by Manatee, so won't be available until Manatee has started):

        # cp -R /tmp/test/root/opt/postgresql /opt/.
        # groupadd -g 907 postgres
        # useradd -u 907 -g postgres postgres
        # echo "postgres    ALL=(ALL) NOPASSWD: /usr/bin/chown, \
            /usr/bin/chmod, /opt/local/bin/chown, /opt/local/bin/chmod" >> \
            /opt/local/etc/sudoers
        # echo "/opt/postgresql/current/bin:$PATH"

1. Get the following details about the cluster:
    1. An IP address from "ifconfig -a".  We'll call this $SELF_IP.  The IP to
        use will depend on your configuration.  The Manatee services will bind to
        this IP, so don't pick a public IP unless that's really what you want.
    1. The $ZK_CONN_STRING mentioned earlier.
    1. A name for this cluster as $SHARD_NAME, which will define the location
        that the cluster's state will be stored in ZooKeeper, so ensure it doesn't
        violate ZooKeeper's conventions.  Either the full path (e.g.
        "/my/test/cluster"), or the top level directory name (e.g. "cluster123",
        in which case we'll prefix "/manatee/" to this choice, making the full
        path "/manatee/cluster123").
    1. The version of PostgreSQL you want to use as $PG_VERSION.  Supported
        options for this are "9.2" or "9.6".

1. Run the setup script

        # ./tools/mkdevsitters $SELF_IP $ZK_CONN_STR $SHARD_NAME $PG_VERSION

1. For each peer ("1", "2", "3"), open up two terminals.  In the first, start
   the sitter:

        # node sitter.js -f devconfs/sitter1/sitter.json | bunyan

   In the second terminal, start the backup server:

        # node backupserver.js -f devconfs/sitter1/backupserver.json | bunyan

If you want to clean everything up (**note: this will destroy all data stored
in these peers!)**, run:

    # for peer in 1 2 3; do zfs destroy -R zones/$(zonename)/data/peer$peer; done

**This command is very destructive!  Be sure you're okay with destroying the
datasets, snapshots, and clones of all of the peers you created before you run
this command.**

Then run:

    # rm -rf devconfs

## Details

This section has more details about the above procedure.

### Provisioning a development zone

We develop Manatee in SmartOS zones running under Triton.  You should be able to
run on standalone SmartOS (i.e., not running under Triton), or even other systems
with ZFS and Postgres installed (e.g., BSD).  Manatee requires access to ZFS
datasets to create snapshots, send streams, and the like, and it also must
run as root.  The former currently rules out the Joyent Public Cloud as a
deployment option.

We deploy Manatee using the multiarch 13.3.1 image (equivalent to image
4aec529c-55f9-11e3-868e-a37707fcbe86).  For development, we recommend using a
zone based on that image, deployed on a network with a ZooKeeper instance
running.  On Triton, be sure to set `delegate_dataset=true` when provisioning.  On
standalone SmartOS, set `delegate_dataset=true` when you invoke "vmadm create".

### Installing packages

You'll need git, GNU make, a compiler toolchain, and some libraries that are
required for building PostgreSQL.  On the above multiarch SmartOS zone, you can
install these with:

        # pkgin in git gmake gcc47 bison flex

PostgreSQL is built from source, which we pull down as a submodule and checkout
at a certain commit to define the version.  Once built in a temporary location,
we move it to a location on the filesystem that our Manatee configs expect.
Checkout is done like so:

    # git submodule add https://github.com/postgres/postgres.git \
        deps/postgresql96 && cd deps/postgresql96 && \
        git checkout ca9cfe && cd -

Building PostgreSQL like so:

    # make -f Makefile.postgres RELSTAGEDIR=/tmp/test \
        DEPSDIR=/root/manatee/deps pg96

And installaing like so:

    # cp -R /tmp/test/root/opt/postgresql /opt/.

Note: Manatee will create a symlink under "/opt/postgresql" to the current
version of PostgreSQL that it expects as "/opt/postgresql/current".  This will
not be available until Manatee has been started for the first time.

### Creating ZFS datasets and configurations

There's a tool inside the repo called "mkdevsitters" which configures the local
system to run three Manatee peers.  You'll have to run the three peers by hand.
The script just creates configuration files and ZFS datasets.  The script must
be run as root.

To use the script, you'll need to know:

* The local IP address you intend to use for these Manatee peers.  If you don't
  know, you can run "ifconfig -a" and pick one.  The tool does not do this
  automatically because common develompent environments have multiple addresses,
  only one of which is correct for this purpose, and it's impossible for the
  script to know which to use.
* The IP address and port of a remote ZooKeeper server.  The port is usually
  2181.  The value you use here is actually a comma-separated list of IP:PORT
  pairs.
* The name of the cluster you're creating.  This is used to identify your
  cluster, and will define the location in ZooKeeper that your cluster's state
  will be stored.  Either choose a full path or an identifier, that latter of
  which will be prefixed with "/manatee/".  Ensure this is unique to your test
  cluster.
* The version of PostgreSQL that you're using.  Either "9.2" or "9.6".

To use this script, as the root user, run:

    # ./tools/mkdevsitters MY_IP ZK_IPS SHARD_NAME PG_VERSION

For example, if my local IP is 172.21.1.74 and there's a ZooKeeper server at
172.21.1.11, with the cluster name "testing123" and version 9.6 of PostgreSQL,
I might run this as root:

    # ./tools/mkdevsitters 172.21.1.74 172.21.1.11:2181 testing123 9.6

This does several things:

* Creates a directory called "devconfs" in the current directory.  "devconfs"
  will contain the configuration and data for each of the three test peers.
* Creates three ZFS datasets under zones/$(zonename)/data, called "peer1",
  "peer2", and "peer3".  The mountpoints for these datasets are in
  "devconfs/datasets".
* Creates configuration files for the Manatee sitter and Manatee backup server
  in "devconfs/sitterN".  Also creates a template postgres configuration file
  in the same directory.

The various services associated with each peer (postgres itself, the sitter's
status API, the backup server, and so on) are all configured to run on different
ports.  The first peer runs on the default ports; subsequent peers run on ports
numbered 10 more than the previous port.  The default postgres port is 5432, so
the first peer runs postgres on port 5432, the second peer runs postgres on port
5442, and the third peer runs postgres on port 5452.


### Running each peer

There are currently two components to run for each peer: the sitter (which also
starts postgres) and the backup server (which is used for bootstrapping
replication for new downstream peers).  To start the first peer, use:

    # node sitter.js -f devconfs/sitter1/sitter.json

You'll probably want to pipe this to bunyan.  Be sure to run this as root.  To
run other peers, replace "sitter1" with "sitter2" or "sitter3".

Similarly, to run the backupserver, use:

    # node backupserver.js -f devconfs/sitter1/backupserver.json

There's also a snapshotter, but running that for development is not yet
documented.
