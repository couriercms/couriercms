defmodule CourierCMSExtension.WordPress.InlineImagesTest do
  use ExUnit.Case, async: true

  alias CourierCMSExtension.WordPress.InlineImages

  test "extracts quoted and unquoted image attributes without rewriting HTML" do
    html = """
    <p>Before</p>
    <IMG CLASS='wp-image-42 hero' SRC="https://example.test/image?a=1&amp;b=2" ALT="A > B">
    <img src=https://example.test/second.png loading=lazy>
    """

    assert [first, second] = InlineImages.extract(html)

    assert first == %{
             "class" => "wp-image-42 hero",
             "src" => "https://example.test/image?a=1&b=2",
             "alt" => "A > B"
           }

    assert second["src"] == "https://example.test/second.png"
    assert second["loading"] == "lazy"
  end

  test "ignores malformed unterminated image tags safely" do
    assert [] = InlineImages.extract(~s(<p>ok</p><img src="https://example.test/image.png"))
  end
end
