OFFLINE SYNAPTICS ARCHIVE LOCATION

The proprietary DisplayLink binary is not included in this package.

For an offline installation, place the unmodified official Synaptics
DisplayLink Ubuntu 6.3 ZIP in this directory with exactly this filename:

DisplayLink-USB-Graphics-Software-for-Ubuntu-6.3.zip

Do not extract, rename internally, patch, or redistribute the proprietary
archive. Its use is governed by the Synaptics DisplayLink EULA.

When the file is absent, install.sh asks for EULA acceptance and downloads the
official 6.3 archive directly from Synaptics. The package never executes the
generic vendor installer in installation mode; it uses extraction-only options
and installs only the validated AArch64 runtime and bundled EVDI source.
