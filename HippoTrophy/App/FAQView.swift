import SwiftUI

/// One question and its answer. The answer is written as if someone had asked
/// out loud, so it names the button they are looking for rather than describing
/// the feature in the abstract.
private struct FAQEntry: Identifiable {
    let question: String
    let answer: String

    var id: String { question }
}

private struct FAQTopic: Identifiable {
    let title: String
    let entries: [FAQEntry]

    var id: String { title }
}

/// Most of what this app can do sits behind a gesture or a small icon, which is
/// exactly the kind of thing nobody finds by looking. The FAQ is the one place
/// that says out loud where those things are.
struct FAQView: View {
    var body: some View {
        List {
            ForEach(Self.topics) { topic in
                Section(topic.title) {
                    ForEach(topic.entries) { entry in
                        DisclosureGroup {
                            Text(entry.answer)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        } label: {
                            Text(entry.question)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
        }
        .navigationTitle("FAQ")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let topics: [FAQTopic] = [
        FAQTopic(
            title: "Workouts",
            entries: [
                FAQEntry(
                    question: "Can I change the editor's settings for one workout?",
                    answer: "Yes. While training, Editor Settings is in the … menu at the top of the workout; otherwise it is the slider icon. What you change there holds for that workout only. Settings → Workout Editor stays what every workout starts with."
                ),
                FAQEntry(
                    question: "How do I repeat a workout I already did?",
                    answer: "Press and hold the workout in the History list and pick Copy Workout. You get a copy dated today, with the same exercises and sets as a starting point, opened for editing right away."
                ),
                FAQEntry(
                    question: "How do I delete a workout?",
                    answer: "Swipe left on it in the History list."
                )
            ]
        ),
        FAQTopic(
            title: "Exercises",
            entries: [
                FAQEntry(
                    question: "How do I delete an exercise?",
                    answer: "Press and hold the exercise card in the workout editor and pick Delete Exercise. Its sets are deleted with it. A plain tap only collapses or expands the exercise, so you cannot lose one by tapping."
                ),
                FAQEntry(
                    question: "The exercise I want is not in the list.",
                    answer: "Your exercise list is the Exercises tab. Add the name there, or use Import to bring in a prepared list. Everything in that list shows up when you add an exercise to a workout."
                ),
                FAQEntry(
                    question: "Can I keep only the exercise I am working on open?",
                    answer: "Yes — turn on Collapse Other Exercises in Settings. Expanding one exercise then folds the others away."
                ),
                FAQEntry(
                    question: "Where do I note something about an exercise?",
                    answer: "The note icon in the exercise header. A filled icon means a note is already there."
                ),
                FAQEntry(
                    question: "What did I lift for this exercise last time?",
                    answer: "An open exercise shows the last time you logged it in a line under its name, for example 3 days ago: 3×8 @ 60 kg. Tapping that line, or the chart icon in the exercise header, opens every earlier entry for that exercise. The same history is available per exercise in the Exercises tab. If you would rather have the room, turn Show Last Performance off in Settings."
                ),
                FAQEntry(
                    question: "How do I see my progress on an exercise?",
                    answer: "Open the exercise history with the chart icon. Above the list, a graph shows one point per workout; touch it to see a workout's number and the set it comes from. The menu above the graph switches between Est. 1RM, Max Weight, Volume and Most Reps, and the choice is kept for every exercise. The graph reads the Weight and Reps fields, so an exercise needs both to have one. Sides logged as L/R get a line each."
                ),
                FAQEntry(
                    question: "What is the Est. 1RM?",
                    answer: "An estimate of the most you could lift for a single rep, worked out from the best set of each workout: weight × (1 + reps ÷ 30). Warm-up sets do not pull it down, and more reps at the same weight count as progress just like more weight. Past about twelve reps the estimate gets rough, but the trend stays readable."
                )
            ]
        ),
        FAQTopic(
            title: "Sets",
            entries: [
                FAQEntry(
                    question: "How do I delete a single set?",
                    answer: "The minus button in the set row. That deletes only that set — the exercise stays."
                ),
                FAQEntry(
                    question: "How do I log the same set again?",
                    answer: "The copy icon in the set row adds another set with the same weight and reps, ready to adjust."
                ),
                FAQEntry(
                    question: "How do I change the order of the sets?",
                    answer: "Drag a set by the handle on the right of its row."
                ),
                FAQEntry(
                    question: "What are the three bars at the end of a set?",
                    answer: "How hard the set felt — one bar for easy, two for normal, three for hard. Tap them to pick another level; it is saved with the set and shows up again in the exercise history."
                )
            ]
        ),
        FAQTopic(
            title: "Bilateral and Unilateral",
            entries: [
                FAQEntry(
                    question: "How do I log an exercise one side at a time?",
                    answer: "Every exercise is bilateral, both sides at once, or unilateral, one side at a time. A unilateral one — Bulgarian Split Squat, or the catalog's forms named with (Unilateral), like Leg Press (Unilateral) — has a badge next to its name; tap it to pick one of its two modes. For an exercise of your own, choose in the Exercises tab: Sides."
                ),
                FAQEntry(
                    question: "What is the difference between the two unilateral modes?",
                    answer: "Unilateral, Same Weight keeps a single list of sets and means the weight counts per side. Unilateral, Log L/R gives you a Left and Right switcher above the sets and logs the two sides apart, for when they differ — or when you train only one side for a while; fill in that side and leave the other empty."
                ),
                FAQEntry(
                    question: "Why does a Same Weight set take two ticks?",
                    answer: "One row stands for both sides, so you tick it once per side: the first tap fills half the circle and starts a short purple Switch Sides rest, the second finishes the set and starts the normal rest. Logged L/R, the same rest follows the first side of a set, when its other side is next. Until then the set counts as not done. A half tick is kept while the app is open. Settings → Rest Between Sides sets the length, or turns it off."
                ),
                FAQEntry(
                    question: "Can I see left and right together?",
                    answer: "Yes. Settings → Show Left and Right, or Editor Settings for one workout, shows an L/R exercise as one list instead of tabs, with an Add button per side. It goes from side to side from the side it starts with, and a side with more sets runs on alone. Drag a set in the list and the order is yours: any order you like, kept in the workout. Tabs keep it but cannot change it."
                ),
                FAQEntry(
                    question: "How do I say which side comes first?",
                    answer: "Starts with, above the sets of a unilateral exercise. A template's own choice comes first; otherwise it proposes the side you started with last time, or Left if there is none. What you pick holds for this workout and is proposed next time. In a template, leave it on Last Time or prescribe a side. The workout's page says which side came first."
                ),
                FAQEntry(
                    question: "Can I switch a mode back?",
                    answer: "Yes, and nothing is deleted — the sets move along. Leaving the L/R log merges left and right into one list, so it asks first when both sides actually hold sets."
                ),
                FAQEntry(
                    question: "How do I compare my two sides?",
                    answer: "Log the exercise L/R: its history and its progress graph show Left and Right apart. A history from before the split into bilateral and unilateral that holds both kinds of entry also gets a Per Side button, which adds the per-side weight in brackets to the bilateral rows."
                )
            ]
        ),
        FAQTopic(
            title: "Fields and Sets",
            entries: [
                FAQEntry(
                    question: "Can an exercise log something other than weight and reps?",
                    answer: "Yes. A set is a row of the exercise's fields. Weight & Reps keeps those two and takes more beside them; Custom is only the fields you pick. Up to six in all — a distance, a duration, a note. Custom also asks whether it has sets: No sets is one entry rather than a list of sets, like a rowing session."
                ),
                FAQEntry(
                    question: "How do I change the fields of an exercise?",
                    answer: "In the Exercises tab, tap the exercise to open its editor: add fields of your own, take them out, or pick Custom to choose all of them. Workouts you already logged get a new field empty and keep everything else."
                ),
                FAQEntry(
                    question: "What happens when I switch an exercise I have logged with several sets to No sets?",
                    answer: "Every set becomes an entry of its own in that workout, in the same order — nothing is lost. Switching back changes nothing."
                ),
                FAQEntry(
                    question: "Can I log the same exercise twice in one workout?",
                    answer: "Yes — add it to the workout a second time and you get a second entry."
                ),
                FAQEntry(
                    question: "What is a superset?",
                    answer: "Two exercises trained by alternating between them — a set of one, then a set of the other, back and forth — rather than finishing one before starting the next. Add Exercise, then Superset, to pick both at once; or long-press an exercise already in the workout and Convert to Superset to pair it with one that is already there. The sets are listed in the order you did them, the lower exercise tinted; drag a set to change that order, and use Add A or Add B for the next one. Each keeps its own mode and history. Left/Right logging is not available inside a superset."
                )
            ]
        ),
        FAQTopic(
            title: "Your List and Your Data",
            entries: [
                FAQEntry(
                    question: "How do I rename or remove an exercise from my list?",
                    answer: "In the Exercises tab, tap an exercise to rename it or change what it logs, swipe left to remove it. A rename follows the exercise through your history; removing one leaves what you logged in place."
                ),
                FAQEntry(
                    question: "I have the same exercise twice under different names. Can I join them?",
                    answer: "The Exercises tab, then Merge Two Exercises. Pick which one goes and which one stays, say which of its fields mean the same, and everything logged with the first moves to the second."
                ),
                FAQEntry(
                    question: "How do I back up my data?",
                    answer: "Backup on the main screen, then Export Backup. Everything you leave switched on lands in one file — you can leave parts out to share just your exercise list, for example. With photos, that file is a ZIP."
                ),
                FAQEntry(
                    question: "How do I import a backup?",
                    answer: "Backup on the main screen, then Import Backup, and pick the exported file, the JSON or the ZIP. You choose what to bring in and whether the workouts are added to what is already there or replace all of it. Where the file and your list disagree about an exercise, you are asked before anything is written."
                )
            ]
        ),
        FAQTopic(
            title: "Sync",
            entries: [
                FAQEntry(
                    question: "What does Sync do?",
                    answer: "It keeps a backup of everything on a WebDAV server of your own: when you finish a workout, and when you leave the app after changing something. The server holds backup.zip, the newest, and a copy for each of the last 14 days in history/. Nothing goes anywhere else, and with Sync off the app never uses the network."
                ),
                FAQEntry(
                    question: "Which server can I use?",
                    answer: "Any WebDAV server reached over HTTPS. With Nextcloud, the address is https://your-cloud/remote.php/dav/files/your-user-name/, and instead of your password you make an app password under Personal Settings → Security. A small WebDAV server in Docker works too. The app makes a folder called HippoTrophy at the address and writes only there."
                ),
                FAQEntry(
                    question: "My server has a certificate I made myself. How does the iPhone trust it?",
                    answer: "Send the certificate of your own certificate authority to the iPhone — the .pem or .crt file, by AirDrop or mail — and install it under Settings → General → VPN & Device Management. Then turn it on under Settings → General → About → Certificate Trust Settings. The app has no way around this on purpose: a certificate the iPhone does not trust is exactly what someone in the middle would show."
                ),
                FAQEntry(
                    question: "Can I sync two iPhones?",
                    answer: "Only one device should write to the server. On another one, download backup.zip and import it under Backup → Import Backup. If a device finds a backup on the server that it did not write, it stops and asks you which one counts."
                )
            ]
        )
    ]
}

#Preview {
    NavigationStack {
        FAQView()
    }
}
