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
    repo_url_suffix => '18.x',
  }
  $python3_pkg = lookup('jupyterhub::python3::package_name')
  ensure_packages([$python3_pkg],
    {
      ensure => 'installed',
    }
  )
}

class jupyterhub::base::install::venv(
  Stdlib::Absolutepath $prefix,
  Stdlib::Absolutepath $python = '/usr/bin/python3',
) {
  file { [$prefix, "${prefix}/bin"]:
    ensure => directory,
  }

  exec { 'jupyterhub_venv':
    command => "${python} -m venv ${prefix}",
    creates => "${prefix}/bin/python",
  }

  $pip_version = lookup('jupyterhub::pip::version')
  $python3_version = lookup('jupyterhub::python3::version')

  exec { 'pip_upgrade_pip':
    command => "${prefix}/bin/pip install --upgrade --no-cache-dir pip==${pip_version}",
    creates => "${prefix}/lib/python${python3_version}/site-packages/pip-${pip_version}.dist-info/",
    require => Exec['jupyterhub_venv'],
  }
}
