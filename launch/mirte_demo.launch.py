from launch import LaunchDescription
from launch.actions import IncludeLaunchDescription
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch_ros.actions import Node
from launch.substitutions import PathJoinSubstitution
from launch_ros.substitutions import FindPackageShare


def generate_launch_description():

    params_file = PathJoinSubstitution([
        FindPackageShare('cs_demo_mirte'),
        'config',
        'easynav_params.yaml',
    ])

    mirte_house = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            PathJoinSubstitution([
                FindPackageShare('cs_demo_mirte'),
                'launch',
                'mirte_house.launch.py',
            ])
        )
    )

    # CoreSense action adapter
    action_node = Node(
        package='cs_demo_mirte',
        executable='action_node',
        name='action',
        output='screen',
    )

    # Room estimation
    room_estimator_node = Node(
        package='cs_demo_mirte',
        executable='room_estimator_node',
        name='room_estimator',
        output='screen',
    )

    # MIRTE execution module.
    # The OWL ontology is located in sysml2owl.
    mirte_module_node = Node(
        package='cs_demo_mirte',
        executable='mirte_module_node',
        name='mirte_module',
        output='screen',
        parameters=[{
            'owl_file': PathJoinSubstitution([
                FindPackageShare('cs_demo_mirte'),
                'ontology',
                'sysml.owl',
            ]),
        }],
    )

    return LaunchDescription([
        mirte_house,
        action_node,
        room_estimator_node,
        mirte_module_node,
    ])