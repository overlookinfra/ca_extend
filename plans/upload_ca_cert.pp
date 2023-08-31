# @summary
#   A plan to upload a given CA certificate to a number of Puppet agent nodes
# @param nodes The targets to upload the certificate to
# @param cert The location of the CA certificate on disk of the local machine
# @return JSON object with two keys: success and failure.
#   Each key contains any number of objects consisting of the agent certname and the output of the upload_file command
plan ca_extend::upload_ca_cert(
  TargetSpec $nodes,
  String     $cert
) {
  # Work around BOLT-1168
  run_plan('ca_extend::get_agent_facts', 'nodes' => $nodes, '_catch_errors' => true)
  $tmp = run_plan('facts', 'targets' => $nodes, '_catch_errors' => true)

  # Extract the ResultSet from an error object
  case $tmp {
    Error['bolt/run-failure']: {
      $results = $tmp.details['result_set']
      $not_ok = $results.error_set
    }
    default: {
      $results = $tmp
      $not_ok = undef
    }
  }

  # The os.family fact should consistantly be "windows" on, well, Windows.
  $windows_targets = $results.ok_set.filter |$n| { "${n.value['os']['family']}" == 'windows' }
  $linux_targets = $results.ok_set.filter |$n| { ! ("${n.value['os']['family']}" == 'windows') }

  $windows_results = upload_file(
    $cert,
    'C:\ProgramData\PuppetLabs\puppet\etc\ssl\certs\ca.pem',
    $windows_targets.map |$item| { $item.target.name },
    '_catch_errors' => true
  )

  $linux_results = upload_file(
    $cert,
    '/etc/puppetlabs/puppet/ssl/certs/ca.pem',
    $linux_targets.map |$item| { $item.target.name },
    '_catch_errors' => true
  )

  # Create a hash for *nix and Windows successful and failed uploads and merge them together
  # filter will return nil if anything doesn't match the lambda, and deep merge will
  # crunch the left hashes if the rightmost value isn't a hash, so check for that
  $good = deep_merge(
    if $linux_results.any |$r| { $r.ok } {
      { 'success' => $linux_results.filter |$result| { $result.ok }.map |$result| {
          { $result.target.name => $result.value }
        }.reduce |$memo, $value| { $memo + $value }
      }
    },
    if $windows_results.any |$r| { $r.ok } {
      { 'success' => $windows_results.filter |$result| { $result.ok }.map |$result| {
          { $result.target.name => $result.value }
        }.reduce |$memo, $value| { $memo + $value }
      }
    }
  )

  $bad = deep_merge(
    if ! $windows_results.ok {
      { 'failure' => $windows_results.filter |$result| { ! $result.ok }.map |$result| {
          { $result.target.name => $result.value }
        }.reduce |$memo, $value| { $memo + $value }
      }
    },
    if ! $linux_results.ok {
      { 'failure' => $linux_results.filter |$result| { ! $result.ok }.map |$result| {
          { $result.target.name => $result.value }
        }.reduce |$memo, $value| { $memo + $value }
      }
    },
    if $not_ok {
      { 'failure' => $not_ok.map |$result| {
          { $result.target.name => $result.value }
        }.reduce |$memo, $value| { $memo + $value }
      }
    }
  )

  return deep_merge($good, $bad)
}
