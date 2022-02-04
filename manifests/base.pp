class jupyterhub::base(Stdlib::Absolutepath $prefix) {
  class { 'jupyterhub::base::install::venv':
    prefix => $prefix
  }

  contain jupyterhub::base::install::packages
  contain jupyterhub::base::install::venv
  Class['jupyterhub::base::install::packages'] -> Class['jupyterhub::base::install::venv']
}

class jupyterhub::base::install::packages {
  class { 'nodejs':
    repo_url_suffix => '12.x',
  }

  ensure_packages(['python3'], {
    ensure => 'installed'
  })
}

class jupyterhub::base::install::venv(
  Stdlib::Absolutepath $prefix,
  Stdlib::Absolutepath $python = '/usr/bin/python3',
) {
  file { [$prefix, "${prefix}/bin"]:
    ensure => directory
  }

  exec { 'jupyterhub_venv':
    command => "${python} -m venv ${prefix}",
    creates => "${prefix}/bin/python",
  }

  $pip_version = lookup('jupyterhub::pip::version')
  $jupyterhub_version = lookup('jupyterhub::jupyterhub::version')
  $batchspawner_version = lookup('jupyterhub::batchspawner::version')

  exec { 'pip_upgrade_pip':
    command => "${prefix}/bin/pip install --upgrade --no-cache-dir pip==${pip_version}",
    creates => "${prefix}/lib/python3.6/site-packages/pip-${pip_version}.dist-info/",
    require => Exec['jupyterhub_venv']
  }

  exec { 'pip_jupyterhub':
    command => "${prefix}/bin/pip install --upgrade --no-cache-dir jupyterhub==${jupyterhub_version}",
    creates => "${prefix}/lib/python3.6/site-packages/jupyterhub-${jupyterhub_version}.dist-info/",
    require => Exec['pip_upgrade_pip']
  }

  exec { 'pip_batchspawner':
    command => "${prefix}/bin/pip install --no-cache-dir batchspawner==${batchspawner_version}",
    creates => "${prefix}/lib/python3.6/site-packages/batchspawner-${batchspawner_version}.dist-info/",
    require => Exec['pip_jupyterhub']
  }
}
