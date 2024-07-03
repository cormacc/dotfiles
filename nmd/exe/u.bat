@ECHO OFF
rem Change to a dir relative to your user profile directory
rem USAGE: 'u dev\emacs' -> cd %USERPROFILE%\dev\emacs
rem
rem Also supports tokenized subdirs, convenient for invocation from other batch files
rem i.e. 'u dev emacs' === 'u dev\emacs'
rem
rem TODO: Update to cache the original path, build a new one, then pushd

cd %USERPROFILE%
FOR %%A IN (%*) DO (
    cd %%A
)
