class jupyterhub::base (
  Stdlib::Absolutepath $prefix,
) {
  include nodejs

  $pip_version = lookup('jupyterhub::pip::version')
  $python3_version = lookup('jupyterhub::python3::version')
  $python3_bin     = lookup('jupyterhub::python3::bin')
  $python3_pkg     = lookup('jupyterhub::python3::pkg')
  $python3_path    = lookup('jupyterhub::python3::path')

  ensure_packages([$python3_pkg])

  file { [$prefix, "${prefix}/bin"]:
    ensure => directory,
  }

  exec { 'jupyterhub_venv':
    command => "${$python3_bin} -m venv ${prefix}",
    creates => "${prefix}/bin/python",
    require => Package[$python3_pkg],
    path    => [$python3_path],
  }

  exec { 'pip_upgrade_pip':
    command => "pip install --upgrade --no-cache-dir pip==${pip_version}",
    creates => "${prefix}/lib/python${python3_version}/site-packages/pip-${pip_version}.dist-info/",
    require => Exec['jupyterhub_venv'],
    path    => ["${prefix}/bin/"],
  }
}
