class { 'r10k':
  version           => '1.2.1',
  sources           => {
    'puppet' => {
      'remote'  => 'https://github.com/open-dai/puppet-environment.git',
      'basedir' => "${::settings::confdir}/environments",
      'prefix'  => false,
    }
  },
  purgedirs         => ["${::settings::confdir}/environments"],
  manage_modulepath => true,
  modulepath        => "${::settings::confdir}/environments/\$environment/modules:/opt/puppet/share/puppet/modules",
}