function lss --description "Show more detailed 'ls' output"
    ls -l --all --human-readable --classify --color=always $argv | less -XRF
end
