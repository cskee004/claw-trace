import { Controller } from "@hotwired/stimulus"

// Handles inline expansion of a trace row in the trace list.
// On first expand, sets turbo-frame src to trigger lazy load.
// Subsequent toggles show/hide already-loaded content without a new request.
export default class extends Controller {
  static targets = ["drawer", "frame", "chevron"]
  static values  = { previewUrl: String }

  toggle(event) {
    if (event.target.closest("a")) return

    const isOpen = !this.drawerTarget.classList.contains("open")
    this.drawerTarget.classList.toggle("open", isOpen)
    this.chevronTarget.setAttribute("aria-expanded", isOpen)
    this.chevronTarget.textContent = isOpen ? "▲" : "▼"

    // Lazy-load: set src only on first open
    if (isOpen && !this.frameTarget.getAttribute("src")) {
      this.frameTarget.setAttribute("src", this.previewUrlValue)
    }
  }
}
