import SwiftUI

// MARK: – Force simulation
//
// A lightweight force-directed layout. Everyone repels everyone (so nodes
// spread out); people who share a tag or context attract (so they cluster);
// a soft pull toward the centre keeps the cloud on screen. No edges are drawn —
// grouping shows up purely as proximity.
//
// Constants are deliberately grouped so we can tune the "feel" easily.

final class CloudSim {
    struct Node { var pos: CGPoint; var vel: CGVector }

    // Tunables
    private let repulsion: CGFloat = 60_000   // how hard nodes push apart (short range)
    private let maxRepulsion: CGFloat = 1_200
    private let attraction: CGFloat = 1.2     // spring stiffness for related pairs
    private let restLength: CGFloat = 96      // preferred distance between related people
    private let centerPull: CGFloat = 0.6     // gentle gravity toward the middle
    private let damping: CGFloat = 0.85
    private let maxSpeed: CGFloat = 620
    private let margin: CGFloat = 44

    private(set) var nodes: [UUID: Node] = [:]
    private var order: [UUID] = []
    private var adjacency: [UUID: Set<UUID>] = [:]
    private var pinned: [UUID: CGPoint] = [:]
    private var lastTick: Date?

    func needsConfigure(for contacts: [Contact]) -> Bool {
        order != contacts.map(\.id)
    }

    func configure(_ contacts: [Contact], size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        var next: [UUID: Node] = [:]
        for c in contacts {
            if let existing = nodes[c.id] {
                next[c.id] = existing                 // keep where it already is
            } else {
                let angle = CGFloat.random(in: 0 ..< (2 * .pi))
                let r = CGFloat.random(in: 20 ... max(40, min(size.width, size.height) / 3))
                next[c.id] = Node(pos: CGPoint(x: center.x + cos(angle) * r,
                                               y: center.y + sin(angle) * r),
                                  vel: .zero)
            }
        }
        nodes = next
        order = contacts.map(\.id)

        var adj: [UUID: Set<UUID>] = [:]
        for i in 0 ..< contacts.count {
            for j in (i + 1) ..< contacts.count where CloudSim.related(contacts[i], contacts[j]) {
                adj[contacts[i].id, default: []].insert(contacts[j].id)
                adj[contacts[j].id, default: []].insert(contacts[i].id)
            }
        }
        adjacency = adj
    }

    /// Two people "have to do with each other" if they share a tag or context.
    private static func related(_ a: Contact, _ b: Contact) -> Bool {
        if let ca = a.context?.lowercased(), let cb = b.context?.lowercased(),
           !ca.isEmpty, ca == cb { return true }
        let ta = Set(a.tags.map { $0.lowercased() })
        let tb = Set(b.tags.map { $0.lowercased() })
        return !ta.isEmpty && !ta.isDisjoint(with: tb)
    }

    func position(_ id: UUID) -> CGPoint { nodes[id]?.pos ?? .zero }
    func pin(_ id: UUID, at p: CGPoint) { pinned[id] = p }
    func unpin(_ id: UUID) { pinned[id] = nil }

    func step(size: CGSize, now: Date) {
        guard size.width > 0, size.height > 0, !order.isEmpty else { return }

        let dt: CGFloat
        if let last = lastTick {
            dt = min(CGFloat(now.timeIntervalSince(last)), 1.0 / 30)
        } else {
            dt = 1.0 / 60
        }
        lastTick = now
        guard dt > 0 else { return }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var force: [UUID: CGVector] = [:]
        for id in order { force[id] = .zero }

        for i in 0 ..< order.count {
            for j in (i + 1) ..< order.count {
                let a = order[i], b = order[j]
                guard let pa = nodes[a]?.pos, let pb = nodes[b]?.pos else { continue }
                var dx = pa.x - pb.x, dy = pa.y - pb.y
                var dist = sqrt(dx * dx + dy * dy)
                if dist < 0.01 {
                    dx = CGFloat.random(in: -1 ... 1); dy = CGFloat.random(in: -1 ... 1); dist = 1
                }
                let ux = dx / dist, uy = dy / dist

                let rep = min(repulsion / (dist * dist), maxRepulsion)
                force[a]?.dx += ux * rep; force[a]?.dy += uy * rep
                force[b]?.dx -= ux * rep; force[b]?.dy -= uy * rep

                if adjacency[a]?.contains(b) == true {
                    let spring = attraction * (dist - restLength)
                    force[a]?.dx -= ux * spring; force[a]?.dy -= uy * spring
                    force[b]?.dx += ux * spring; force[b]?.dy += uy * spring
                }
            }
        }

        for id in order {
            guard var node = nodes[id] else { continue }
            if let p = pinned[id] {
                node.pos = p; node.vel = .zero; nodes[id] = node; continue
            }
            var f = force[id] ?? .zero
            f.dx += (center.x - node.pos.x) * centerPull
            f.dy += (center.y - node.pos.y) * centerPull

            node.vel.dx = (node.vel.dx + f.dx * dt) * damping
            node.vel.dy = (node.vel.dy + f.dy * dt) * damping

            let speed = sqrt(node.vel.dx * node.vel.dx + node.vel.dy * node.vel.dy)
            if speed > maxSpeed {
                node.vel.dx *= maxSpeed / speed
                node.vel.dy *= maxSpeed / speed
            }

            node.pos.x = min(max(node.pos.x + node.vel.dx * dt, margin), size.width - margin)
            node.pos.y = min(max(node.pos.y + node.vel.dy * dt, margin), size.height - margin)
            nodes[id] = node
        }
    }
}

// MARK: – Floating cloud view

struct PeopleCloudView: View {
    let contacts: [Contact]
    var onSelect: (Contact) -> Void

    @State private var sim = CloudSim()
    private let space = "people.cloud"

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                if sim.needsConfigure(for: contacts) {
                    sim.configure(contacts, size: geo.size)
                }
                sim.step(size: geo.size, now: timeline.date)

                return ZStack {
                    ForEach(contacts) { contact in
                        CloudNode(contact: contact)
                            .position(sim.position(contact.id))
                            .gesture(
                                DragGesture(coordinateSpace: .named(space))
                                    .onChanged { sim.pin(contact.id, at: $0.location) }
                                    .onEnded { _ in sim.unpin(contact.id) }
                            )
                            .onTapGesture { onSelect(contact) }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .coordinateSpace(name: space)
        .overlay {
            if contacts.isEmpty {
                Text("No one here yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: – A single node (thin ring + first name)

private struct CloudNode: View {
    let contact: Contact

    var body: some View {
        VStack(spacing: 5) {
            SwiftUI.Circle()
                .fill(Color(.systemBackground))
                .overlay {
                    SwiftUI.Circle().strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 1.5)
                }
                .overlay {
                    Text(initials)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .frame(width: 46, height: 46)
                .shadow(color: .black.opacity(0.05), radius: 3, y: 1)

            Text(firstName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    private var firstName: String {
        contact.name.split(separator: " ").first.map(String.init) ?? contact.name
    }

    private var initials: String {
        contact.name
            .split(separator: " ")
            .compactMap(\.first)
            .prefix(2)
            .map(String.init)
            .joined()
            .uppercased()
    }
}
