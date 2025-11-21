#!/bin/env csh

# This is a C Shell script that automates the process of copying an entire
# directory into the local clipboard as a base64-encoded tarball. It is a
# workaround for remote systems that lack modern conveniences like `xclip`.
#
# The main dependency is xemacs, obviously, but it also depends on BSD `tar` and
# `base64`. When you run this command, an xemacs window should briefly appear.
# It may remain open for a few moments or longer depending on how much data you
# are copying. After it finishes loading your clipboard, it will close on its
# own. Then, immediately use the `get_files.tcl` script locally to save the files
# that are in your clipboard.

# Check if a directory argument is provided.
if ($#argv == 0) then
  echo "Usage: $0 <directory>" >&2
  exit 1
endif

# The following busy little `xemacs` command does four main things:
# 1. Generate a tarball of the chosen directory.
# 2. Encode it into plain text with `base64`.
# 3. Load the text into xemacs.
# 3. Copy it from xemacs into the local clipboard.
#
# You'll notice an xemacs window popup briefly when executing this command,
# but it should vanish before it even appears to populate with text. This is
# normal. After it runs, you can paste the text into a document, decode the
# base64, then uncompress the tarball. If it fails, there is a chance the
# delay in the lisp code isn't set high enough. In that case, `sleep-for`
# should be increased from `0.5` to `1` or something larger.
xemacs -eval "(progn (shell-command "\""tar -cz '$1' | base64"\"" t) (mark-whole-buffer) (x-own-selection (buffer-substring (point-min) (point-max))) (sleep-for 0.5) (kill-emacs))"
