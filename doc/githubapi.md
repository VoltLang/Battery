# Getting archives.

To get an archive link of a repository, use

    GET /repos/:owner/:repo/:archive_format/:ref

Where `:owner` is the Owner of the repository, `:repo` is the repository, `:archive_format` is either `tarball` or `zipball`, and `:ref` is a git reference (usually `master`).

For example.

	curl -L https://api.github.com/repos/VoltLang/Volta/zipball/master >master.zip

Will get the contents of the master branch of VoltLang/Volta as a zipfile. The initial GET will return a redirect to the actual file. The code will be in a folder in the root :owner-:repo-$shahash, e.g. `VoltaLang-Volta-76aff47`.
