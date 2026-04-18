import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["drawer", "chevron"]

  toggle(event) {
    if (event.target.closest("a")) return
    event.stopPropagation()

    const isOpen = this.drawerTarget.classList.toggle("open")
    if (this.hasChevronTarget) {
      this.chevronTarget.setAttribute("aria-expanded", isOpen)
      this.chevronTarget.textContent = isOpen ? "▲" : "▼"
    }
  }
}
