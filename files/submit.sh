#!/bin/bash
#SBATCH --time=0
#SBATCH --output={homedir}/jupyterhub_slurmspawner_%j.log
#SBATCH --job-name=spawner-jupyterhub
#SBATCH --chdir={homedir}
#SBATCH --mem=512M
#SBATCH --cpus-per-task=1
#SBATCH --export={keepvars}
unset XDG_RUNTIME_DIR
module restore

# Environment setup
VENV="/dev/shm/jupyter"
rm -rf $VENV
tar xf /project/jupyter_singleuser.tar.gz -C /dev/shm

# Launch jupyterhub single server
source $VENV/bin/activate
{cmd}
