class jupyterhub::base::install (
  Stdlib::Absolutepath $prefix,
) {
  $python3_version = lookup('jupyterhub::python3::version')

  exec { 'jupyterhub_venv':
    command     => "uv venv -p ${python3_version} ${prefix}",
    creates     => "${prefix}/bin/python",
    require     => Archive['jh_install_uv'],
    path        => ['/opt/uv/bin'],
    environment => ['XDG_DATA_HOME=/opt/uv/share'],
  }
}
