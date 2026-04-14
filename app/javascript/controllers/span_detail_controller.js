import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["drawer", "chevron", "logsFrame"]

  connect() {
    this.drawerTarget.classList.add("open")
    if (this.hasChevronTarget) this.chevronTarget.textContent = "▾"
    this.element.querySelector("[aria-expanded]")?.setAttribute("aria-expanded", "true")
  }

  toggle(event) {
    const isOpen = this.drawerTarget.classList.toggle("open")
    event.currentTarget.setAttribute("aria-expanded", isOpen)
    if (this.hasChevronTarget) this.chevronTarget.textContent = isOpen ? "▾" : "▸"
    if (isOpen && this.hasLogsFrameTarget && !this.logsFrameTarget.getAttribute("src")) {
      this.logsFrameTarget.src = this.logsFrameTarget.dataset.logsUrl
    }
  }
}
