import Foundation

/// Footage-type rules set by Devona.
///  - a face or person but no sound                                   -> B-roll
///  - no person, background noise or chatter                           -> B-roll
///  - sustained speech over many shots (people, objects, settings)
///    that carries straight through the cuts                           -> Voice over (VO)
///  - no person, sustained speech in the clip's own location audio     -> Off-screen dialogue (OFFSCREEN)
///  - people in some shots, sustained speech in location audio         -> A-roll (AROLL)
///  Plus: a face to camera in most frames with speech                  -> Talking head (TALK)
enum Classifier {
    static func classify(fps: Double, a: Analysis) -> (FootageType, Bool) {
        let person = max(a.faceShare, a.personShare)
        let bigFace = a.faceShare >= 0.5 && a.faceSize >= 0.04
        let sustained = a.speechShare >= 0.5 && a.longestRun >= 2.5
        if fps >= 100 { return (.broll, true) }                      // slow motion
        if sustained {
            if a.narrated { return (.vo, true) }                     // many shots, one narration
            if bigFace { return (.talk, true) }                      // talking to camera
            if person == 0 { return (.offscreen, a.cuts < 3) }       // nobody on screen
            return (.aroll, a.cuts < 3)                              // people in some shots
        }
        if person > 0 && a.speechShare < 0.15 { return (.broll, true) } // person, no sound
        if bigFace && a.speechShare >= 0.3 { return (.talk, false) }
        if a.speechShare >= 0.35 { return (.broll, false) }           // in between: ask
        return (.broll, true)                                         // noise or chatter
    }
}
