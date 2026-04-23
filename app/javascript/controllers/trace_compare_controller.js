import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "button", "count"]
  static values  = { compareUrl: String }

  toggle() {
    const checked = this.checkboxTargets.filter(cb => cb.checked)
    const n = checked.length

    this.countTarget.textContent = n === 0 ? "" : `${n} selected`

    const btn = this.buttonTarget
    if (n === 2) {
      const [a, b] = checked.map(cb => cb.value)
      btn.href = `${this.compareUrlValue}?a=${a}&b=${b}`
      btn.dataset.turboFrame = "_top"
      btn.classList.remove("opacity-40", "pointer-events-none")
      btn.classList.add("cursor-pointer")
    } else {
      btn.href = "#"
      btn.classList.add("opacity-40", "pointer-events-none")
      btn.classList.remove("cursor-pointer")
    }
  }

  // Prevent row-expand click from firing when clicking the checkbox cell
  stop(event) {
    event.stopPropagation()
  }
}
