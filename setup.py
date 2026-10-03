from setuptools import find_packages, setup
from glob import glob

package_name = 'cs_demo_mirte'

setup(
    name=package_name,
    version='0.1.0',
    packages=find_packages(),

    data_files=[
        (
            'share/ament_index/resource_index/packages',
            ['resource/' + package_name],
        ),
        (
            'share/' + package_name,
            ['package.xml'],
        ),
        (
            'share/' + package_name + '/launch',
            glob('launch/*.launch.py'),
        ),
        (
            'share/' + package_name + '/config',
            glob('config/*', recursive=True),
        ),
        (
            'share/' + package_name + '/ontology',
            glob('ontology/**/*', recursive=True),
        ),
        (
            'share/' + package_name + '/model',
            glob('model/**/*', recursive=True),
        ),
    ],

    install_requires=[
        'setuptools',
        'rdflib',
    ],

    zip_safe=True,

    entry_points={
        'console_scripts': [
            'action_node = cs_demo_mirte.action_node:main',
            'mirte_module_node = cs_demo_mirte.mirte_module_node:main',
        ],
    },
)