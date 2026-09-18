# frozen_string_literal: true

# Libleptris 1.9.200-201 (the lockstep): pull ERROR events carry
# text_len (every event path now length-drives its text), and the
# binding's pull reader adopts the length-driven contract — the
# spec pins the error message actually arriving.
RSpec.describe "libleptris 1.9.201 surfaces (lockstep)" do
  it "a pull ERROR event carries its message text (1.9.200)" do
    parser = Leptris::XML::Pull::Parser.parse("<a><b></a>")
    event = nil
    parser.each do |ev|
      event = ev
      break if ev.type == :error || ev.type == :end_document
    end
    expect(event.type).to eq(:error)
    expect(event.text).to be_a(String)
    expect(event.text.length).to be > 0
    expect(event.text.encoding).to eq(Encoding::UTF_8)
  ensure
    parser&.free
  end
end
