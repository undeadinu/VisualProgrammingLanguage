//
//  DisplayNodeCanvas.swift
//  VPL
//
//  Created by Nathan Flurry on 3/26/18.
//  Copyright © 2018 Nathan Flurry. All rights reserved.
//

import UIKit

class DisplayNodeCanvasOverlay: UIView {
    weak var canvas: DisplayNodeCanvas?
    
    init(frame: CGRect, canvas: DisplayNodeCanvas) {
        self.canvas = canvas
        
        super.init(frame: frame)
        
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ rect: CGRect) {
        guard let canvas = canvas else {
            print("No canvas to draw overlay.")
            return
        }
        guard let ctx = UIGraphicsGetCurrentContext() else {
            print("No graphics context.")
            return
        }
        
        for node in canvas.nodes {
            for socket in node.sockets {
                // Draw a connection
                if let target = socket.draggingTarget {
                    // Draw a line to where the user is currently dragging
                    let startPosition = socket.convert(CGPoint.zero, to: self)
                    drawSocketConnection(
                        context: ctx,
                        from: CGPoint(x: startPosition.x + socket.frame.width / 2, y: startPosition.y + socket.frame.height / 2),
                        to: CGPoint(x: startPosition.x + target.x, y: startPosition.y + target.y)
                    )
                } else if let targetSocket = findTarget(forSocketType: socket.type) {
                    // Draw a line between the sockets
                    let startPosition = socket.convert(CGPoint.zero, to: self)
                    let endPosition = targetSocket.convert(CGPoint.zero, to: self)
                    drawSocketConnection(
                        context: ctx,
                        from: CGPoint(x: startPosition.x + socket.frame.width / 2, y: startPosition.y + socket.frame.height / 2),
                        to: CGPoint(x: endPosition.x + targetSocket.frame.width / 2, y: endPosition.y + targetSocket.frame.height / 2)
                    )
                }
            }
        }
    }
    
    /// Finds a display node socket that matches a socket type.
    func findTarget(forSocketType socketType: DisplayNodeSocketType) -> DisplayNodeSocket? {
        guard let canvas = canvas else {
            print("Missing canvas.")
            return nil
        }
        
        // Find another socket with the same type
        switch socketType {
        case .controlFlow(let trigger):
            guard let triggerTarget = trigger.target else {
                return nil
            }
            
            // Search nodes for a target that matches this target
            for node in canvas.nodes {
                for socket in node.sockets {
                    if case let .controlFlow(otherTrigger) = socket.type {
                        if triggerTarget === otherTrigger {
                            return socket
                        }
                    }
                }
            }
        case .dataFlow(let value):
            guard let valueTarget = value.target else {
                return nil
            }
            
            // Search nodes for a target that matches this target
            for node in canvas.nodes {
                for socket in node.sockets {
                    if case let .dataFlow(otherValue) = socket.type {
                        if valueTarget === otherValue {
                            return socket
                        }
                    }
                }
            }
        }
        
        // No match
        return nil
    }
    
    /// Draws a line between two points indicating a socket position
    func drawSocketConnection(context ctx: CGContext, from: CGPoint, to: CGPoint) {
        ctx.setLineCap(.round)
        ctx.setLineWidth(6)
        ctx.setStrokeColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.addLines(between: [from, to])
        ctx.strokePath()
    }
}

class DisplayNodeCanvas: UIView {
    var nodes: [DisplayNode]
    
    var overlay: DisplayNodeCanvasOverlay!
    
    var updateCallback: (() -> Void)?
    
    override init(frame: CGRect) {
        // Create new node list
        nodes = []
        
        super.init(frame: frame)
        
        // Style the view
        backgroundColor = .clear
        
        // Add the overlay
        overlay = DisplayNodeCanvasOverlay(frame: bounds, canvas: self)
        overlay.autoresizingMask = UIViewAutoresizing.flexibleWidth.union(UIViewAutoresizing.flexibleHeight)
        addSubview(overlay)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Only allow user interaction if interacting with subviews. This way
        // the drawing canvas behind this view can still be interacted with.
        let result = super.hitTest(point, with: event)
        if result == self { return nil }
        return result
    }
    
    /// Assembles all of the code.
    func assemble() -> String {
        var output = ""
        
        // Assemble each function
        for node in nodes {
            if let node = node.node as? FunctionNode {
                output += node.assemble()
                
                output += "\n\n"
            }
        }
        
        return output
    }
    
    /// Adds a node to the canvas.
    func insert(node: DisplayNode) {
        assert(!nodes.contains(node))
        assert(node.canvas == nil)
        
        // Set the canvas
        node.canvas = self
        
        // Insert into the list and view
        nodes.append(node)
        addSubview(node)
        
        // Perform updated
        updated(node: node)
    }
    
    /// Called when any interaction occurs with the node and it needs to be
    /// updated.
    func updated(node: DisplayNode) {
        // Bring node to front under overlay
        bringSubview(toFront: node)
        bringSubview(toFront: overlay)
        
        // Redraw overlay
        overlay.setNeedsDisplay()
        
        // Call update
        updateCallback?()
    }
    
    /// Removes a ndoe from the canvas.
    func remove(node: DisplayNode) {
        assert(nodes.contains(node))
        assert(node.canvas == self)
        
        // Remove the node from the list
        guard let nodeIndex = nodes.index(where: { $0 === node }) else {
            print("Failed to find node in list.")
            return
        }
        nodes.remove(at: nodeIndex)
        node.removeFromSuperview()
        
        // Destroy the node
        node.node.destroy()
        
        // Update
        overlay.setNeedsDisplay()
        updateCallback?()
    }
    
    /// Creates a connection between sockets based on the current dragging
    /// position.
    func finishConnection(socket: DisplayNodeSocket) {
        guard let target = socket.draggingTarget else {
            print("No target for socket.")
            return
        }
        
        // Find a socket dislplay that matches the point
        for node in nodes {
            if node.point(inside: node.convert(target, from: socket), with: nil) {
                for targetSocket in node.sockets {
                    if targetSocket.point(inside: targetSocket.convert(target, from: socket), with: nil) {
                        // Attempt to connect the sockets
                        if socket.canConnectTo(socket: targetSocket) {
                            socket.connectTo(socket: targetSocket)
                        }
                    }
                }
            }
        }
        
        // Remove the target
        socket.draggingTarget = nil
        
        // Update
        updateCallback?()
    }
}