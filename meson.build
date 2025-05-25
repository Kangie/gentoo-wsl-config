project('gentoo-wsl-config', 'c', version: '0.1.0', meson_version: '>=1.1.0') # meson.options
# This is not the 'c' you're looking for

# This project creates and installs the WSL configuration files for Gentoo Linux.

configure_file(
    input: 'wsl.conf.in',
    output: 'wsl.conf',
    configuration: configuration_data({
        'systemd': get_option('systemd').to_string().to_lower(),
    }),
    install_dir: get_option('sysconfdir'),
    install_mode: 'rw-r--r--',
)

configure_file(
    input: 'wsl-distribution.conf.in',
    output: 'wsl-distribution.conf',
    configuration: configuration_data({
        'libdir': get_option('libdir'),
    }),
    install_dir: get_option('sysconfdir'),
    install_mode: 'rw-r--r--',
)

install_data(
    'oobe.sh',
    install_dir: get_option('libexecdir') / 'wsl',
    install_mode: 'rwxr--r--',
)

lib_files = files('gentoo.ico', 'terminal-profile.json')

install_data(
    lib_files,
    install_dir: get_option('libdir') / 'wsl',
    install_mode: 'rw-r--r--',
)
