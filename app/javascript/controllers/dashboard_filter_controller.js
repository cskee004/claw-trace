import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["customForm"]

  showCustom() {
    this.customFormTarget.hidden = false
  }
}
