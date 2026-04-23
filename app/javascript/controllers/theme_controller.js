import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "clawtrace-theme"

export default class extends Controller {
  connect() {
    const stored = localStorage.getItem(STORAGE_KEY)
    const preferred = window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark"
    this.#apply(stored || preferred)
  }

  toggle() {
    const next = this.element.dataset.theme === "light" ? "dark" : "light"
    localStorage.setItem(STORAGE_KEY, next)
    this.#apply(next)
  }

  #apply(theme) {
    this.element.dataset.theme = theme
  }
}
