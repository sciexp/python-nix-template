# conda

The files in this directory are automatically generated from the
[pyproject.toml](../pyproject.toml) by running

```sh
just -n conda-lock
```

in the repository root directory.

To create a corresponding conda environment, use the environment and platform
specific lockfile to construct a command of the form

```sh
mamba create --name <env> --file <explicit spec file>
```

For example, for a conda environment named `python-nix-template` and the `dev` environment
from the [pyproject.toml](../pyproject.toml) on x86_64-linux architecture run

```sh
mamba create --name python-nix-template --file dev_linux-64_conda_spec.txt
```

These environments will be missing packages that are sourced from pypi in the
[pixi.lock](../pixi.lock). See [pixi export explicit
spec](https://pixi.sh/dev/reference/cli/#project-export-conda-explicit-spec) for
details.
