#!/bin/bash
{% if account %}#SBATCH --account={{account}}{% endif %}
#SBATCH --time={{runtime}}
#SBATCH --output={{homedir}}/.jupyterhub_slurmspawner_%j.log
#SBATCH --job-name=spawner-jupyterhub
#SBATCH --chdir={{homedir}}
#SBATCH --mem={{memory}}
#SBATCH --cpus-per-task={{nprocs}}
#SBATCH --export={{keepvars}}
{% if oversubscribe %}#SBATCH --oversubscribe{% endif %}
{% if reservation %}#SBATCH --reservation={{reservation}}{% endif %}
#SBATCH --gres={{gpus}}
unset XDG_RUNTIME_DIR

# Disable variable export with sbatch
export SBATCH_EXPORT=NONE

# Create user pip install folder
export PIP_PREFIX=${SLURM_TMPDIR}
SITE="${PIP_PREFIX}/lib/$(ls /opt/ipython-kernel/lib/)/site-packages"
mkdir -p $SITE
export PATH="/opt/jupyterhub/bin:${PATH}"
export PATH=${PIP_PREFIX}/bin:${PATH}
export PYTHONPATH=${SITE}:${PYTHONPATH}

# Activate kernel virtual environment
export VIRTUAL_ENV_DISABLE_PROMPT=1
source /opt/ipython-kernel/bin/activate

# Launch jupyterhub single server
{{cmd}}
