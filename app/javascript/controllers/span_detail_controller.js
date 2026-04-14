import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["drawer", "logsFrame"]

  toggle(event) {
    const isOpen = this.drawerTarget.classList.toggle("open")
    event.currentTarget.setAttribute("aria-expanded", isOpen)
    if (isOpen && this.hasLogsFrameTarget && !this.logsFrameTarget.getAttribute("src")) {
      this.logsFrameTarget.src = this.logsFrameTarget.dataset.logsUrl
    }
  }
}
