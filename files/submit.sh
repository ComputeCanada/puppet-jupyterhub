#!/bin/bash
#SBATCH --time=0
#SBATCH --output={homedir}/.jupyterhub_slurmspawner_%j.log
#SBATCH --job-name=spawner-jupyterhub
#SBATCH --chdir={homedir}
#SBATCH --mem=450M
#SBATCH --cpus-per-task=1
#SBATCH --export={keepvars}
#SBATCH --oversubscribe
unset XDG_RUNTIME_DIR
module restore

# Environment setup
TARBALL="/project/jupyter_singleuser.tar.gz"
VENV="$SLURM_TMPDIR/$(tar --exclude="*/*" -tf $TARBALL)"
rm -rf $VENV
tar xf $TARBALL -C $SLURM_TMPDIR

# Disable virtualenv prompt addition
export VIRTUAL_ENV_DISABLE_PROMPT=1

# Disable variable export with sbatch
export SBATCH_EXPORT=NONE

# Launch jupyterhub single server
source $VENV/bin/activate
{cmd}
