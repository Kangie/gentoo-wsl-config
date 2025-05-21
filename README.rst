##############################################################
Gentoo Linux Windows Subsystem for Linux (WSL) 2 Configuration
##############################################################

This repository contains a configuration for Gentoo Linux running on Windows Subsystem for Linux (WSL) 2.
It is designed to provide a seamless experience for users who want to run (or try) Gentoo on their Windows machines.

This package should be installed in the WSL 2 environment; it is not intended to be used on a native Gentoo installation.
It still requires that users follow an abridged version of the Gentoo Handbook to set up their system—we only provide config and an OOBE script to help users get started.

The configuration is designed to be used with WSL 2 (``>=2.4.4+``) and has not been tested with WSL 1.

.. Tip::

    The easiest way to install Gentoo for WSL is via the Windows Store.
    This package is included in the installation and will be automatically configured for you.

Developers
===========

This repository is maintained by the Gentoo Linux community. If you would like to contribute, please feel free to open an issue or pull request.

If you have any questions or suggestions, please reach out to us on the Gentoo forums or IRC channels.

.. Tip::

    Gentoo's ``catalyst`` tool is used to build a WSL-compatible distro image.
    The WSL ``spec`` file will automatically pull in this package and configure it apprapriately.
    You can use ``catalyst`` to build a custom Gentoo WSL image with your own configuration, if desired.
    See the `catalyst <https://wiki.gentoo.org/wiki/Catalyst>`_ wiki page for more information.

Local Development
-----------------

To build the package locally, you will need to have the following dependencies installed:

* ``meson build`` and ``ninja`` (or ``samurai``), or
* ``muon``

The WSL `build a custom distro <https://learn.microsoft.com/en-us/windows/wsl/build-custom-distro#test-the-distribution-locally>`_ page contains intructions for testing a custom WSL distro locally.

Icon Generation
---------------

Since us linux-folks don't really deal with Windows icon files, we need some way to generate them from one of our vector formats.
This is done using the ``convert`` command from the ``imagemagick`` package.

To generate icon(s), run the following command:

.. code-block:: console

    larry@gentoo:~/gentoo-wsl-config$ magick convert -density 384 -background none gentoo-signet.svg -define icon:auto-resize gentoo.ico

End users
=========

End users should install Gentoo for WSL via the Windows Store; this package will be included in the image.

If not using the Windows Store, you can install this package via the command line:

.. code-block:: console

    root@wsl# emerge sys-apps/gentoo-wsl-config

SystemD support
===============

The default configuration for Gentoo WSL (as shipped in the Windows Store) does not include SystemD.

Installing this package with the ``systemd`` USE flag (or manually compiling with ``-Dsystemd=true``)
will enable SystemD support in WSL, however it is not recommended for most users;
the following services must be disabled or masked as they are known to cause issues:

* ``systemd-resolved.service``
* ``systemd-networkd.service``
* ``NetworkManager.service``
* ``systemd-tmpfiles-setup.service``
* ``systemd-tmpfiles-clean.service``
* ``systemd-tmpfiles-clean.timer``
* ``systemd-tmpfiles-setup-dev-early.service``
* ``systemd-tmpfiles-setup-dev.service``
* ``tmp.mount``

.. Tip::
    You should be able to use ``catalyst`` to build a custom Gentoo WSL image with SystemD support, if this is desired.

See `here <https://learn.microsoft.com/en-us/windows/wsl/build-custom-distro#systemd-recommendations>`_ for more information.
