#!/usr/bin/env tclsh

# This is a Tcl/Tk script that copy files from a remote system using the clipboard
# that is shared between your remote device and local device. It depends on `tcllib`,
# falling back to unix commands if necessary.
# - On Windows: `winget install --id Magicsplat.TclTk -e`
# - On Debian/Ubuntu: `apt install tcl tk`
#
# To use it, run `./get_files.csh <directory>` on the remote device to load the
# remote files into your clipboard, then run `tclsh ./get_files.tcl` on your local
# machine to save the files that are in your clipboard. If the contents of your
# clipboard changes in the meantime, the command will fail. So use the commands
# back-to-back, and remember to manually type the commands rather than copy/pasting
# them.

package require Tcl 8.5
package require base64

if {$argc != 1} {
    puts stderr "Usage: $argv0 <output_directory>"
    exit 1
}
set output_dir [lindex $argv 0]

# ensure output dir exists
if {![file exists $output_dir]} {
    if {[catch {file mkdir $output_dir} err]} {
        puts stderr "Error creating directory $output_dir: $err"
        exit 1
    }
} elseif {![file isdirectory $output_dir]} {
    puts stderr "$output_dir is not a directory."
    exit 1
}

# clipboard (Tk)
if {[catch {package require Tk} err]} {
    puts stderr "Tk package required for clipboard access: $err"
    exit 1
}
set base64_data [clipboard get]

# decode base64 (returns binary string)
if {[catch {::base64::decode $base64_data} decoded_data]} {
    puts stderr "Error decoding base64 data: $decoded_data"
    exit 1
}

# Determine a temp directory in a portable way
if {[info exists ::env(TEMP)] && $::env(TEMP) ne ""} {
    set tmpdir $::env(TEMP)
} elseif {[info exists ::env(TMP)] && $::env(TMP) ne ""} {
    set tmpdir $::env(TMP)
} else {
    # fallback to current working directory
    set tmpdir [pwd]
}

# ensure tmpdir exists
if {![file exists $tmpdir]} {
    set tmpdir [pwd]
}

# create a reasonably unique temporary filename
set tmpname [file join $tmpdir [format "b64tar-%d-%d.bin" [clock seconds] [pid]]]

# write decoded bytes to the temp file
set fh [open $tmpname "wb"]
fconfigure $fh -translation binary
puts -nonewline $fh $decoded_data
close $fh

# helper: try to delete temp file (with a couple retries on Windows)
proc _try_delete {path} {
    set attempts 0
    while {$attempts < 3} {
        if {![file exists $path]} { return 1 }
        if {[catch {file delete -force $path} err]} {
            incr attempts
            # small sleep; 'after' works in tclsh (keeps things portable)
            after 150
            continue
        } else {
            return 1
        }
    }
    # final attempt failed
    puts stderr "Warning: could not delete temp file $path: $err"
    return 0
}

# open file to probe magic bytes (we'll close it promptly)
set fh_probe [open $tmpname "rb"]
fconfigure $fh_probe -translation binary -buffering full
set head [read $fh_probe 2]
seek $fh_probe 0
close $fh_probe

set is_gzip 0
if {[string length $head] >= 2} {
    # binary scan must assign variables, so use a temp list
    binary scan $head c2 a b
    if {$a == 31 && $b == 139} { set is_gzip 1 }
}

# If we have tcllib tar available, prefer it
if {[catch {package require tar} tarErr] == 0} {
    if {$is_gzip} {
        # gzipped tar: try to use zlib if available
        if {[catch {package require zlib} zerr] == 0} {
            # open channel, push gunzip, feed to tar::untar as channel
            set fh [open $tmpname "rb"]
            fconfigure $fh -translation binary -buffering full
            if {[catch {zlib push gunzip $fh} pushErr]} {
                close $fh
                puts stderr "zlib push gunzip failed: $pushErr"
                # fall through to external-tar fallback below
            } else {
                if {[catch {::tar::untar $fh -chan -dir $output_dir} terr]} {
                    # make sure to pop and close even on error
                    catch {zlib pop $fh}
                    close $fh
                    puts stderr "Error extracting gzipped tar via tcllib tar: $terr"
                    _try_delete $tmpname
                    exit 1
                }
                # success: pop and close
                catch {zlib pop $fh}
                close $fh
                _try_delete $tmpname
                puts "Tarball extracted to $output_dir (using tcllib tar + zlib)"
                exit 0
            }
        } else {
            # no zlib: don't call ::tar::untar on gzipped bytes — fallback to external tar below
            # (we purposely fall through to external-tar fallback)
        }
    } else {
        # not gzipped: direct file extraction via tcllib tar
        if {[catch {::tar::untar $tmpname -dir $output_dir} terr2]} {
            puts stderr "Error extracting tar via tcllib tar: $terr2"
            _try_delete $tmpname
            exit 1
        }
        _try_delete $tmpname
        puts "Tarball extracted to $output_dir (using tcllib tar)"
        exit 0
    }
}

# If we reach here, either tcllib tar is not available, or we couldn't use it for gzipped tar.
# Try external tar variants that understand gzipped archives.
set ok 0
set triedCmds {
    {tar -xzf \$tmpname -C \$output_dir}
    {tar -xf  \$tmpname -C \$output_dir}
    {gzip -d -c \$tmpname | tar -x -C \$output_dir}
}

foreach cmd $triedCmds {
    # build argv list and substitute
    set parts [split $cmd]
    set parts [lmap p $parts {string map [list \$tmpname $tmpname \$output_dir $output_dir] $p}]
    if {[catch {eval exec $parts} out]} {
        # try next
        continue
    } else {
        set ok 1
        break
    }
}

# final cleanup
_try_delete $tmpname

if {!$ok} {
    puts stderr "Error: could not extract archive. Tried tcllib tar (and zlib) and several external commands but none succeeded."
    puts stderr "If this is a gzipped tarball, ensure either 'zlib' (tcllib) is installed so tcllib's tar can gunzip it, or install a platform 'tar' that understands gzip (tar.exe on Win10, Git for Windows, msys, etc.)."
    exit 1
}

puts "Tarball extracted to $output_dir (using external tar/gzip)"
exit 0

