import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["drawer"]

  toggle(event) {
    const isOpen = this.drawerTarget.classList.toggle("open")
    event.currentTarget.setAttribute("aria-expanded", isOpen)
  }
}
