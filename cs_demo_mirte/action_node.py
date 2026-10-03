"""MIRTE demonstrator action adapter, bridge for CS-FE ActionSpecification
"""
import re
import rclpy
from rclpy.node import Node
from std_msgs.msg import String


class ActionNode(Node):
    def __init__(self):
        super().__init__('action')
        self.declare_parameter('input_topic', '/mission/effect')
        self.declare_parameter('output_topic', '/mirte/action')
        inp = self.get_parameter('input_topic').value
        out = self.get_parameter('output_topic').value
        self.pub = self.create_publisher(String, out, 10)
        self.sub = self.create_subscription(String, inp, self.on_effect, 10)
        self.get_logger().info(f'Action adapter: {inp} -> {out}')

    def on_effect(self, msg):
        effect = msg.data.strip().lower()
        match = re.fullmatch(r'reach[_-](kitchen|bedroom|living[_-]?room|dining[_-]?room)', effect)
        if not match:
            self.get_logger().warn(f'Ignoring unsupported mission effect: {msg.data}')
            return
        room = match.group(1).replace('_', '')
        aliases = {
            'kitchen': 'kitchen',
            'bedroom': 'bedroom',
            'livingroom': 'living_room',
            'diningroom': 'dining_room',
        }
        command = String()
        command.data = aliases[room]
        self.pub.publish(command)
        self.get_logger().info(f'Action reach_{room} -> room={command.data}')


def main(args=None):
    rclpy.init(args=args)
    node = ActionNode()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()
