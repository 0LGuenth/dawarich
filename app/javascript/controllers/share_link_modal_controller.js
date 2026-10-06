import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["familySection", "magicPhraseSection"]

  connect() {
    this.updateAudience()
  }

  close(event) {
    event.preventDefault()

    const frame = this.element.closest("turbo-frame#share-link-modal")
    if (frame) {
      frame.innerHTML = ""
    } else {
      this.element.remove()
    }
  }

  toggleAudience() {
    this.updateAudience()
  }

  updateAudience() {
    const audienceSelect = this.element.querySelector('select[name="shared_link[audience]"]')
    if (!audienceSelect) return

    const isFamily = audienceSelect.value === 'family'
    if (this.hasFamilySectionTarget) {
      this.familySectionTarget.classList.toggle('hidden', !isFamily)
    }
    if (this.hasMagicPhraseSectionTarget) {
      this.magicPhraseSectionTarget.classList.toggle('hidden', isFamily)
    }
  }
}
