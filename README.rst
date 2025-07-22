##############################################################
Gentoo Linux Windows Subsystem for Linux (WSL) 2 Configuration
##############################################################

This repository contains configuration for Gentoo Linux running on Windows Subsystem for Linux (WSL) 2.
It is designed to provide a seamless experience for users who want to run (or try) Gentoo on their Windows machines.

This package should be installed in the WSL 2 environment; it is not intended to be used on a native Gentoo installation.
It still requires that users follow an abridged version of the Gentoo Handbook to set up their system—we only provide configuration
and an OOBE script to help users get started.

The configuration is designed to be used with WSL 2 (``>=2.4.4+``) and has not been tested with WSL 1.

.. Tip::

    The easiest way to install Gentoo for WSL is via the Windows Store, or by importing a tarball (``.wsl`` file) directly from Gentoo.
    This package is included in the installation and will be automatically configured for you.

Contributing
============

This repository is maintained by the Gentoo Linux community. If you would like to contribute, please feel free to log a bug, open an issue, or submit a patch or pull request.

If you have any questions or suggestions, please reach out to us on the Gentoo forums or IRC channels:

- #gentoo on Libera.Chat (IRC) - general Gentoo support
- #gentoo-wsl on Libera.Chat (IRC) - Gentoo WSL support
- `Gentoo Forums <https://forums.gentoo.org/>`_
- `Gentoo Bugzilla <https://bugs.gentoo.org/>`_ - for reporting bugs or issues

End users
=========

End users should install Gentoo for WSL via the Windows Store, or by fetching a tarball (``.wsl`` file) directly from Gentoo;
this package will be included in the installation and will be configured automatically.

If you are building a WSL container manually, you can install this package via the command line:

.. code-block:: console

    root@wsl# emerge sys-apps/gentoo-wsl-config


Developers
===========

Gentoo's ``catalyst`` tool is used to build a WSL-compatible distro image.
The WSL ``spec`` file will automatically pull in this package and configure it appropriately.
You can use ``catalyst`` to build a custom Gentoo WSL image with your own configuration, if desired.
See the `catalyst <https://wiki.gentoo.org/wiki/Catalyst>`_ wiki page for more information.

Local Development
-----------------

To build the package locally, you will need to have the following dependencies installed:

* ``meson build`` and ``ninja`` (or ``samurai``), or
* ``muon``

The WSL `build a custom distro <https://learn.microsoft.com/en-us/windows/wsl/build-custom-distro#test-the-distribution-locally>`_
page contains instructions for testing a custom WSL distro locally.

The ``oobe.sh`` script is the main entry point for the out-of-box experience (OOBE) and will be executed automatically when the WSL distro is launched for the first time.

For development and testing purposes, the script accepts ``--dry-run`` and ``--debug`` options to help developers test their changes without affecting the system state.

Catalyst-generated tarballs alongside a local ebuild repository may be used to test pre-release configurations in a 'real-world' environment; rename a catalyst tarball to end in ``.wsl`` and double-click it to install.

Icon Generation
---------------

Since Linux users don't typically deal with Windows icon files, we need some way to generate them from one of our vector formats.
This is done using the ``convert`` command from the ``imagemagick`` package.

To generate icon(s), run the following command:

.. code-block:: console

    larry@gentoo:~/gentoo-wsl-config$ magick convert -density 384 -background none gentoo-signet.svg -define icon:auto-resize gentoo.ico

Pre-commit Hook for oobe.sh
----------------------------

A pre-commit hook is provided in the ``.githooks/`` directory to help contributors avoid committing invalid shell scripts.
This hook checks that ``oobe.sh`` is valid Bash and optionally runs ``shellcheck`` if available.

**To enable the pre-commit hook:**

.. code-block:: shell

   git config core.hooksPath .githooks

This will cause Git to use the hooks in ``.githooks/`` for all operations in this repository.

**What the hook does:**

- Blocks commits if ``oobe.sh`` has Bash syntax errors.
- Runs ``shellcheck`` on ``oobe.sh`` if available, blocking the commit on lint errors.
- Prints a message if ``shellcheck`` is not installed.

**Manual check:**

You can manually check your script before committing with:

.. code-block:: shell

   bash -n oobe.sh
   shellcheck oobe.sh  # if installed

Contributions
=============

Contributions are welcome! Please ensure your changes pass the pre-commit checks before submitting a pull request.
