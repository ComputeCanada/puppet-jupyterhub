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

  $jupyterhub_version = lookup('jupyterhub::jupyterhub::version')
  $batchspawner_url = lookup('jupyterhub::batchspawner::url')

  exec { 'pip_jupyterhub':
    command => "${prefix}/bin/pip install --upgrade --no-cache-dir jupyterhub==${jupyterhub_version}",
    creates => "${prefix}/lib/python3.6/site-packages/jupyterhub-${jupyterhub_version}.dist-info/",
    require => Exec['jupyterhub_venv']
  }

  exec { 'pip_batchspawner':
    command => "${prefix}/bin/pip install --no-cache-dir ${batchspawner_url}",
    creates => "${prefix}/lib/python3.6/site-packages/batchspawner/",
    require => Exec['pip_jupyterhub']
  }
}
