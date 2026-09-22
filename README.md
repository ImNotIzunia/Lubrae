# Lubrae

[![CI](https://github.com/ImNotIzunia/Lubrae/actions/workflows/ci.yml/badge.svg)](https://github.com/ImNotIzunia/Lubrae/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/Bash-4.4%2B-4EAA25.svg)](https://www.gnu.org/software/bash/)

Lubrae is an interactive Bash tool for wiping a disk, partition or file.

## Requirements

- Linux distribution with Bash support
- Bash 4.4 or later
- Standard Unix tools such as `dd`, `stat` and `realpath` 
- Root privileges are required to wipe disks

Additional tools may be required depending on the selected target and filesystem:

- `lsblk` and `blockdev` for disks
- `parted` for formatting disks
- `mkfs.ext4` for ext4
- `mkfs.xfs` for xfs
- `mkfs.vfat` for vfat
- `mkfs.exfat` for exfat
- `mkfs.ntfs` for ntfs

Lubrae checks for missing tools before starting the operation. On Debian/Ubuntu systems, it can offer to install missing packages using `apt`.

## Installation

Lubrae is a single Bash file. You can download it directly from the repository or clone the repository and run it from there.

```bash
# Only the script
curl -fsSLO https://raw.githubusercontent.com/ImNotIzunia/Lubrae/main/lubrae.sh

chmod +x lubrae.sh

# All the repository
git clone https://github.com/ImNotIzunia/Lubrae.git

cd Lubrae

chmod +x lubrae.sh
```

You can run it by using `./lubrae.sh` or use the makefile command

```bash
make run
```

## Usage

To start Lubrae and wipe a disk:

```Bash
sudo ./lubrae.sh
```

To wipe a regular file without root privileges:

```Bash
./lubrae.sh --file FILE
```

You can also display the available options:

```Bash
./lubrae.sh --help
./lubrae.sh --version
```

`-f`, `-h` and `-V` are short forms of `--file`, `--help` and `--version`.

Before starting the wipe, Lubrae displays a summary of the selected options and asks you to enter the exact path of the target.

If the entered path does not exactly match the selected target, the operation is cancelled.

> **Warning** Lubrae is a destructive tool. Make sure you have selected the correct target before confirming the operation.

### Testing with a file

If you want to try Lubrae without using a real disk, you can create a test file:

```bash
truncate -s 100M test.img
./lubrae.sh --file test.img
```

This allows you to test the application without requiring root privileges or modifying a real disk.

## Safety

Lubrae includes several safeguards to reduce the risk of accidentally wiping the wrong target:

- The system disk cannot be selected
- Mounted disks cannot be selected
- Disk status is checked again before wiping
- The target must be confirmed by entering its exact path
- Only writable regular files can be selected as files
- Missing tools are detected before the first write

A failed dd operation immediately stops the wipe
After a wipe, the target is deselected

>**Important**: Wiping an SSD, NVMe drive or USB flash drive with dd is not a reliable method of securely erasing all previous data. Due to wear leveling and other drive-level mechanisms, some data may remain accessible.

## Development

### Running tests

Lubrae includes unit, integration and block-device tests.

You can run the complete test suite with:

```Bash
make test
```

You can also run a ShellCheck using:

```Bash
make lint
```

To run both ShellCheck and the tests:

```Bash
make check
```

Both tests are integrared into the CI workflow.

## Contribution

This is a personal project maintained by a single contributor.

All issues and pull requests are welcome. Please keep security and stability in mind when contributing.

You can also support the project by offering me a coffee !

<div align="center">

[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/imnotizunia)

</div>

## License

MIT License.