// Build ID and version for the About screen. CI fills them in before compiling
// (ID = short commit SHA, version from manifest.xml); locally they stay "dev".
module Build {
    const ID = "dev";
    const VERSION = "dev";
    // Store name; on the watch the app is called just "Ahead" (strings.xml)
    const FULL_NAME = "Ahead: What's That Landmark";
    const AUTHOR = "McLEI";
    const CONTACT = "garmin.dev@leisoft.cz";
}
