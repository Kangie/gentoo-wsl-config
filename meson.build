project('gentoo-wsl-config', 'c', version: '0.1.3', meson_version: '>=1.1.0')  # meson.options
# This is not the 'c' you're looking for

# This project creates and installs the WSL configuration files for Gentoo Linux.

configure_file(
    input: 'wsl.conf.in',
    output: 'wsl.conf',
    configuration: configuration_data(
        {
            'systemd': get_option('systemd').to_string().to_lower(),
            'version': meson.project_version(),
        },
    ),
    install_dir: get_option('sysconfdir'),
    install_mode: 'rw-r--r--',
)

configure_file(
    input: 'wsl-distribution.conf.in',
    output: 'wsl-distribution.conf',
    configuration: configuration_data(
        {
            'datadir': get_option('prefix') / get_option('datadir'),
            'libexecdir': get_option('prefix') / get_option('libexecdir'),
            'version': meson.project_version(),
        },
    ),
    install_dir: get_option('sysconfdir'),
    install_mode: 'rw-r--r--',
)

install_data(
    'oobe.sh',
    install_dir: get_option('libexecdir') / 'wsl',
    install_mode: 'rwxr--r--',
)

misc_files = files('gentoo.ico', 'terminal-profile.json')

install_data(
    misc_files,
    install_dir: get_option('datadir') / 'wsl',
    install_mode: 'rw-r--r--',
)
