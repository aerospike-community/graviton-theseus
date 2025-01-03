from sos.report.plugins import Plugin, RedHatPlugin
import os
import glob
import shutil
import zipfile


class Aerospike(Plugin, RedHatPlugin):
    plugin_name = "aerospike"
    profiles = ('system',)
    packages = ('aerospike-server-enterprise')

    def setup(self):
        collect_info_cmd = "asadm -e collectinfo"
        self.add_cmd_output(collect_info_cmd)
        self.add_copy_spec("/etc/aerospike/aerospike.conf")
        self.add_copy_spec("/var/log/aerospike/aerospike.log")

    def collect(self):
        def find_latest_file(file_list):
            # Get the creation times of the files
            files_with_times = [(file, os.path.getctime(file)) for file in file_list]

            if len(files_with_times) <= 0:
                return None

            # Find the file with the latest creation time
            latest_file = max(files_with_times, key=lambda x: x[1])

            return latest_file[0]

        def unzip_file_in_memory(file):
            """
            Unzips the provided zip file in memory.

            :param file: the name of the zip file.
            :return: A dictionary with filenames as keys and file content as values.
            """
            unzipped_files = {}

            with zipfile.ZipFile(file) as z:
                for file_info in z.infolist():
                    with z.open(file_info) as file:
                        unzipped_files[file_info.filename] = file.read().decode('utf-8')

            return unzipped_files

        collect_info_files = glob.glob("/tmp/collect_info_*/")
        latest = find_latest_file(collect_info_files)
        if latest is None:
            return

        with os.scandir(latest) as entries:
            files = [entry.name for entry in entries if entry.is_file()]

            for file in files:
                if file.endswith(".zip"):
                    unzipped_files = unzip_file_in_memory(os.path.join(latest, file))
                    for file in unzipped_files:
                        with self.collection_file(file) as pfile:
                            pfile.write(unzipped_files[file])

                else:
                    with self.collection_file(file) as pfile:
                        with open(os.path.join(latest, file)) as collectinfo_file:
                            shutil.copyfileobj(collectinfo_file, pfile)

