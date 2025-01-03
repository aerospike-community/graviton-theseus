from sos.report.plugins import Plugin, RedHatPlugin


class Aerospike(Plugin, RedHatPlugin):
    plugin_name = "aerolab"
    profiles = ('system',)
    packages = ('aerolab')

    def setup(self):
        self.add_cmd_output('aerolab inventory list')
        self.add_cmd_output('aerolab config backend')
        self.add_cmd_output('aerolab config defaults')
        self.add_copy_spec("/root/.aerolab/telemetry/uuid")

    def collect(self):
        with self.collection_file('inventory.json') as pfile:
            inventory = self.exec_cmd('aerolab inventory list -j', stderr=False)
            if not inventory['status'] == 0:
                pfile.write(f"Unable to get inventory: {{inventory['output']}}")
                return
            pfile.write(inventory['output'])
