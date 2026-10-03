"""
MIRTE semantic room navigation module.
"""

import math
from pathlib import Path

import rclpy
from rclpy.node import Node

from std_msgs.msg import String
from geometry_msgs.msg import PoseStamped

from rdflib import (
    Graph,
    Namespace,
    RDF,
    RDFS,
    OWL,
)

from yolo_msgs.msg import DetectionArray

from easynav_goalmanager_py import GoalManagerClient
from easynav_goalmanager_py.goal_manager_client import ClientState


class MirteModule(Node):

    def __init__(self):
        super().__init__('mirte_module')

        # ==================================================================
        # Parameters
        # ==================================================================

        self.declare_parameter('owl_file', '')
        self.declare_parameter('command_topic', '/mirte/action')
        self.declare_parameter('map_frame', 'map')
        self.declare_parameter(
            'yolo_topic',
            '/yolo/detections_3d',
        )
        self.declare_parameter(
            'yolo_confidence_threshold',
            0.5,
        )

        owl_file = self.get_parameter(
            'owl_file'
        ).value

        if not owl_file:
            self.get_logger().fatal(
                'No OWL file specified. '
                'Set the "owl_file" parameter.'
            )
            raise RuntimeError(
                'Missing owl_file parameter'
            )

        self.map_frame = self.get_parameter(
            'map_frame'
        ).value

        self.yolo_confidence_threshold = float(
            self.get_parameter(
                'yolo_confidence_threshold'
            ).value
        )

        # ==================================================================
        # OWL semantic model
        # ==================================================================

        self.owl_graph = self._load_ontology(
            owl_file
        )

        self.rooms = self._load_rooms(
            self.owl_graph
        )

        if not self.rooms:
            self.get_logger().fatal(
                f'No room navigation poses found in OWL: '
                f'{owl_file}'
            )
            raise RuntimeError(
                'No rooms found in OWL ontology'
            )

        self.room_rules = self._load_room_rules(
            self.owl_graph
        )

        # ==================================================================
        # EasyNav Goal Manager
        # ==================================================================

        self.goal_manager = GoalManagerClient(self)

        # ==================================================================
        # Current semantic mission
        # ==================================================================

        self.goal_room = None
        self.goal_pose = None

        self.navigation_finished = False
        self.room_verified = False

        # Semantic evidence accumulated during the current mission.
        self.observed_objects = set()

        self.room_belief = 0.0

        # ==================================================================
        # Commands
        # ==================================================================

        command_topic = self.get_parameter(
            'command_topic'
        ).value

        self.create_subscription(
            String,
            command_topic,
            self.on_room,
            10,
        )

        # ==================================================================
        # YOLO perception
        # ==================================================================

        yolo_topic = self.get_parameter(
            'yolo_topic'
        ).value

        self.create_subscription(
            DetectionArray,
            yolo_topic,
            self.on_yolo_detections,
            10,
        )

        # ==================================================================
        # Navigation status monitor
        # ==================================================================

        self.status_timer = self.create_timer(
            0.1,
            self.check_navigation_status,
        )

        self.get_logger().info(
            f'Loaded room poses from OWL: '
            f'{self.rooms}'
        )

        self.get_logger().info(
            f'Loaded OWL room rules: '
            f'{self.room_rules}'
        )

        self.get_logger().info(
            f'YOLO topic: {yolo_topic} | '
            f'confidence threshold: '
            f'{self.yolo_confidence_threshold:.2f}'
        )

        self.get_logger().info(
            f'map={self.map_frame} | '
            f'command_topic={command_topic}'
        )

    # ======================================================================
    # OWL loading
    # ======================================================================

    def _load_ontology(self, filename):

        filename = str(
            Path(filename).expanduser()
        )

        self.get_logger().info(
            f'Loading MIRTE ontology: {filename}'
        )

        if not Path(filename).exists():
            raise FileNotFoundError(
                f'OWL ontology does not exist: '
                f'{filename}'
            )

        graph = Graph()

        graph.parse(
            filename,
            format='turtle',
        )

        return graph

    # ======================================================================
    # Room discovery
    # ======================================================================

    def _load_rooms(self, graph):

        MIRTE = Namespace(
            'https://coresense.eu/mirte#'
        )

        rooms = {}

        # ------------------------------------------------------------------
        # Discover concrete room individuals from OWL.
        #
        # No room names are hard-coded here.
        #
        # Any individual with navigationX/Y/Theta is considered a
        # navigable room instance.
        # ------------------------------------------------------------------

        for room in graph.subjects(
            MIRTE.navigationX,
            None,
        ):

            x = self._literal_value(
                graph,
                room,
                MIRTE.navigationX,
            )

            y = self._literal_value(
                graph,
                room,
                MIRTE.navigationY,
            )

            theta = self._literal_value(
                graph,
                room,
                MIRTE.navigationTheta,
            )

            room_name = self._local_name(
                room
            )

            if x is None or y is None or theta is None:

                self.get_logger().warning(
                    f'Room {room_name} has no complete '
                    f'navigation pose'
                )

                continue

            try:

                rooms[room_name] = {
                    'uri': room,
                    'x': float(x),
                    'y': float(y),
                    'theta': float(theta),
                }

            except (TypeError, ValueError):

                self.get_logger().warning(
                    f'Invalid navigation pose for '
                    f'{room_name}: '
                    f'x={x}, y={y}, theta={theta}'
                )

        self.get_logger().info(
            f'OWL room poses: {rooms}'
        )

        return rooms

    # ======================================================================
    # Room classification rules
    # ======================================================================

    def _load_room_rules(self, graph):

        rules = {}

        for room_name, room_data in self.rooms.items():

            room_uri = room_data['uri']

            required_objects = set()

            # The concrete individual has a type such as:
            #
            #   kitchen a Kitchen
            #
            # The classification rule belongs to Kitchen, not directly
            # to the individual kitchen.

            room_classes = list(
                graph.objects(
                    room_uri,
                    RDF.type,
                )
            )

            for room_class in room_classes:

                required_objects.update(
                    self._extract_required_objects(
                        graph,
                        room_class,
                    )
                )

            if required_objects:

                rules[room_name] = required_objects

                self.get_logger().info(
                    f'OWL room rule: '
                    f'{room_name} requires '
                    f'{sorted(required_objects)}'
                )

        return rules

    def _extract_required_objects(
        self,
        graph,
        room_class,
    ):

        required = set()

        # Rules generated by OWLWriter are represented as:

        #   RoomType rdfs:subClassOf [
        #       a owl:Restriction ;
        #       owl:onProperty mirte:Contains ;
        #       owl:someValuesFrom mirte:ObjectType
        #   ]

        for restriction in graph.objects(
            room_class,
            RDFS.subClassOf,
        ):

            if (
                restriction,
                RDF.type,
                OWL.Restriction,
            ) not in graph:
                continue

            on_property = graph.value(
                restriction,
                OWL.onProperty,
            )

            if on_property is None:
                continue

            # Only semantic containment rules matter here.
            if (
                self._local_name(on_property)
                != 'Contains'
            ):
                continue

            object_class = graph.value(
                restriction,
                OWL.someValuesFrom,
            )

            if object_class is None:
                continue

            required.add(
                self._local_name(
                    object_class
                )
            )

        return required

    # ======================================================================
    # YOLO perception
    # ======================================================================

    def on_yolo_detections(self, msg):

        newly_detected = set()

        for detection in msg.detections:

            if (
                detection.score
                < self.yolo_confidence_threshold
            ):
                continue

            obj = self._normalize_yolo_object(
                detection.class_name
            )

            if obj:
                newly_detected.add(obj)

        # --------------------------------------------------------------
        # Accumulate evidence.
        #
        # A later frame without the object does NOT erase previous
        # evidence from the current room-reaching mission.
        # --------------------------------------------------------------

        self.observed_objects.update(
            newly_detected
        )

        self.get_logger().info(
            f'YOLO objects: '
            f'{sorted(self.observed_objects)}'
        )

        # Only semantic verification is allowed after navigation.
        if self.navigation_finished:
            self._verify_current_room()

    @staticmethod
    def _normalize_yolo_object(class_name):

        if not class_name:
            return None

        normalized = (
            class_name
            .strip()
            .lower()
            .replace('_', '')
            .replace('-', '')
            .replace(' ', '')
        )

        aliases = {
            'bed': 'Bed',

            'fridge': 'Fridge',
            'refrigerator': 'Fridge',

            'oven': 'Oven',

            'cup': 'Cup',

            'tv': 'TV',
            'television': 'TV',

            'chair': 'Chair',

            'diningtable': 'DiningTable',
            'table': 'DiningTable',

            'sofa': 'Sofa',
        }

        return aliases.get(
            normalized
        )

    # ======================================================================
    # Room verification
    # ======================================================================

    def _verify_current_room(self):

        if not self.navigation_finished:
            return

        if self.goal_room is None:
            return

        required = self.room_rules.get(
            self.goal_room
        )

        if not required:

            self.get_logger().warning(
                f'No OWL classification rule for '
                f'{self.goal_room}'
            )

            return

        matched = (
            required &
            self.observed_objects
        )

        self.room_belief = (
            len(matched) /
            len(required)
        )

        self.get_logger().info(
            f'Verifying {self.goal_room}: '
            f'matched={sorted(matched)} '
            f'required={sorted(required)} '
            f'belief={self.room_belief:.2f}'
        )

        # All required semantic evidence is present.
        if matched == required:

            self.room_verified = True

            self.get_logger().info(
                f'ROOM VERIFIED: '
                f'{self.goal_room} '
                f'(YOLO + OWL)'
            )

            self._finish_room_action()

    # ======================================================================
    # Commands
    # ======================================================================

    def on_room(self, msg):

        requested_room = msg.data.strip()

        if not requested_room:
            self.get_logger().warning(
                'Received empty room command'
            )
            return

        # --------------------------------------------------------------
        # Case-insensitive lookup.
        #
        # The ontology remains the source of truth.
        # We do not maintain a list of concrete rooms here.
        # --------------------------------------------------------------

        room_key = None

        for candidate in self.rooms:

            if (
                candidate.lower()
                == requested_room.lower()
            ):
                room_key = candidate
                break

        # Also tolerate the common snake_case spelling.
        if room_key is None:

            normalized = (
                requested_room
                .replace('_', '')
                .lower()
            )

            for candidate in self.rooms:

                candidate_normalized = (
                    candidate
                    .replace('_', '')
                    .lower()
                )

                if (
                    candidate_normalized
                    == normalized
                ):
                    room_key = candidate
                    break

        if room_key is None:

            self.get_logger().error(
                f'Unknown room: '
                f'{requested_room}. '
                f'Available rooms: '
                f'{list(self.rooms)}'
            )

            return

        pose_data = self.rooms[
            room_key
        ]

        # --------------------------------------------------------------
        # Start a new semantic mission.
        # --------------------------------------------------------------

        self.navigation_finished = False
        self.room_verified = False

        self.observed_objects.clear()
        self.room_belief = 0.0

        # --------------------------------------------------------------
        # Build PoseStamped from OWL.
        # --------------------------------------------------------------

        goal = PoseStamped()

        goal.header.stamp = (
            self.get_clock()
            .now()
            .to_msg()
        )

        goal.header.frame_id = self.map_frame

        goal.pose.position.x = (
            pose_data['x']
        )

        goal.pose.position.y = (
            pose_data['y']
        )

        goal.pose.position.z = 0.0

        theta = pose_data.get(
            'theta',
            0.0,
        )

        # Yaw -> quaternion.
        goal.pose.orientation.x = 0.0
        goal.pose.orientation.y = 0.0
        goal.pose.orientation.z = math.sin(
            theta / 2.0
        )
        goal.pose.orientation.w = math.cos(
            theta / 2.0
        )

        # --------------------------------------------------------------
        # Handle previous EasyNav state.
        # --------------------------------------------------------------

        state = (
            self.goal_manager.get_state()
        )

        if state in (
            ClientState.NAVIGATION_FINISHED,
            ClientState.NAVIGATION_REJECTED,
            ClientState.NAVIGATION_FAILED,
            ClientState.NAVIGATION_CANCELLED,
            ClientState.ERROR,
        ):

            self.goal_manager.reset()

        # --------------------------------------------------------------
        # Send goal to EasyNav.
        # --------------------------------------------------------------

        self.goal_manager.send_goal(
            goal
        )

        self.goal_room = room_key
        self.goal_pose = goal

        self.get_logger().info(
            f'REACH {room_key}: '
            f'goal=('
            f'{goal.pose.position.x:.2f}, '
            f'{goal.pose.position.y:.2f}, '
            f'{theta:.2f}) '
            f'-> EasyNav'
        )

    # ======================================================================
    # EasyNav status
    # ======================================================================

    def check_navigation_status(self):

        if self.goal_room is None:
            return

        state = (
            self.goal_manager.get_state()
        )

        if (
            state
            == ClientState.ACCEPTED_AND_NAVIGATING
        ):

            self.get_logger().debug(
                f'Navigating to '
                f'{self.goal_room}'
            )

            return

        if (
            state
            == ClientState.NAVIGATION_FINISHED
        ):

            result = (
                self.goal_manager
                .get_result()
            )

            self.get_logger().info(
                'Navigation successfully finished'
            )

            self.get_logger().info(
                f'Navigation reached '
                f'{self.goal_room}: '
                f'{result.status_message}'
            )

            # ----------------------------------------------------------
            # Navigation is finished.
            #
            # Only now is semantic room verification enabled.
            # ----------------------------------------------------------

            self.navigation_finished = True

            self._verify_current_room()

            return

        if (
            state
            == ClientState.NAVIGATION_FAILED
        ):

            result = (
                self.goal_manager
                .get_result()
            )

            self.get_logger().error(
                f'NAVIGATION FAILED for '
                f'{self.goal_room}: '
                f'{result.status_message}'
            )

            self._clear_mission()

            return

        if (
            state
            == ClientState.NAVIGATION_CANCELLED
        ):

            result = (
                self.goal_manager
                .get_result()
            )

            self.get_logger().warning(
                f'NAVIGATION CANCELLED for '
                f'{self.goal_room}: '
                f'{result.status_message}'
            )

            self._clear_mission()

            return

        if state == ClientState.ERROR:

            result = (
                self.goal_manager
                .get_result()
            )

            self.get_logger().error(
                f'EASYNAV ERROR for '
                f'{self.goal_room}: '
                f'{result.status_message}'
            )

            self._clear_mission()

            return

    # ======================================================================
    # Mission completion
    # ======================================================================

    def _finish_room_action(self):

        if self.goal_room is None:
            return

        room = self.goal_room

        self.get_logger().info(
            f'REACH ROOM SUCCESS: '
            f'{room} verified by '
            f'YOLO + OWL'
        )

        self._clear_mission()

    def _clear_mission(self):

        self.goal_room = None
        self.goal_pose = None

        self.navigation_finished = False
        self.room_verified = False

        self.observed_objects.clear()
        self.room_belief = 0.0

    # ======================================================================
    # RDF helpers
    # ======================================================================

    @staticmethod
    def _literal_value(
        graph,
        subject,
        predicate,
    ):

        values = list(
            graph.objects(
                subject,
                predicate,
            )
        )

        if not values:
            return None

        return values[0].toPython()

    @staticmethod
    def _local_name(uri):

        text = str(uri)

        if '#' in text:
            return text.rsplit(
                '#',
                1,
            )[1]

        if '/' in text:
            return text.rsplit(
                '/',
                1,
            )[1]

        return text

    # ======================================================================
    # Shutdown
    # ======================================================================

    def destroy_node(self):

        if hasattr(
            self,
            'goal_manager',
        ):

            state = (
                self.goal_manager
                .get_state()
            )

            if (
                state
                == ClientState.ACCEPTED_AND_NAVIGATING
            ):

                self.get_logger().info(
                    'Cancelling active '
                    'EasyNav navigation'
                )

                self.goal_manager.cancel()

        super().destroy_node()


def main(args=None):

    rclpy.init(args=args)

    node = MirteModule()

    try:
        rclpy.spin(node)

    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()