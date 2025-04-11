#!/usr/bin/env tclsh

# This script depends on several applications:
# - tclsh   (`winget install --id Magicsplat.TclTk -e` or `apt install tcl tk`)
# - tar     (`winget install --id GnuWin32.Tar -e`)
# - openssl (`winget install --id FireDaemon.OpenSSL -e`)

if {$argc != 1} {
    puts stderr "Usage: $argv0 <output_directory>"
    exit 1
}

set output_dir [lindex $argv 0]

if {![file exists $output_dir]} {
    if {[catch {file mkdir $output_dir} err]} {
        puts stderr "Error creating directory $output_dir: $err"
        exit 1
    }
} elseif {![file isdirectory $output_dir]} {
    puts stderr "$output_dir is not a directory."
    exit 1
}

# Get the clipboard contents (platform-specific)
if {[catch {package require Tk} err]} {
    puts stderr "Tk package required for clipboard access: $err"
    exit 1
}

set base64_data [clipboard get]

# Decode the base64 data and untar it directly
if {[catch {open "|openssl base64 -d | tar -xz -C $output_dir" w} in]} {
    puts stderr "Error processing data: $in"
    exit 1
}
puts $in $base64_data
flush $in
close $in

puts "Tarball extracted to $output_dir"

exit

