import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["drawer", "chevron"]

  connect() {
    this.drawerTarget.classList.add("open")
    if (this.hasChevronTarget) this.chevronTarget.textContent = "▾"
  }

  toggle(event) {
    const isOpen = this.drawerTarget.classList.toggle("open")
    event.currentTarget.setAttribute("aria-expanded", isOpen)
    if (this.hasChevronTarget) this.chevronTarget.textContent = isOpen ? "▾" : "▸"
  }
}
