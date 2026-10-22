# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, '#display_name' do
  it 'joins available nonblank name parts' do
    expect(build(:user, first_name: ' Ada ', last_name: ' Lovelace ').display_name).to eq('Ada Lovelace')
    expect(build(:user, first_name: nil, last_name: 'Hopper').display_name).to eq('Hopper')
    expect(build(:user, first_name: 'Grace', last_name: ' ').display_name).to eq('Grace')
  end

  it 'uses email when both names are missing or whitespace' do
    user = build(:user, first_name: ' ', last_name: nil)
    expect(user.display_name).to eq(user.email)
  end
end

RSpec.describe User, '#initial' do
  it 'uses the first character of display name when available' do
    expect(build(:user, first_name: 'Ada', last_name: 'Lovelace').initial).to eq('A')
    expect(build(:user, first_name: 'bob', email: 'alice@example.com').initial).to eq('B')
  end

  it 'falls back to the first character of email when names are missing or whitespace' do
    expect(build(:user, first_name: nil, last_name: nil, email: 'charlie@example.com').initial).to eq('C')
    expect(build(:user, first_name: ' ', last_name: ' ', email: 'dave@example.com').initial).to eq('D')
  end

  it 'falls back to ? when display name and email are missing' do
    expect(build(:user, first_name: nil, last_name: nil, email: '').initial).to eq('?')
  end
end
