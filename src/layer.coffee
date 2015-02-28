Point = require './point'

module.exports =
class Layer
  constructor: (@source, @transform) ->
    @transform.initialize(@source)
    @regions = @buildRegions()
    @source.onDidChange?(@sourceDidChange.bind(this))

  buildRegions: (sourceStartPosition=Point.ZERO, sourceEndPosition=@source.getEndPosition()) ->
    targetStartPosition = @fromPositionInLayer(sourceStartPosition, @source)
    regions = []

    while sourceStartPosition.isLessThan(sourceEndPosition)
      region = @transform.getNextRegion({sourceStartPosition, targetStartPosition})
      break unless region.sourceTraversal.isGreaterThan(Point.ZERO) or region.targetTraversal.isGreaterThan(Point.ZERO)
      sourceStartPosition = sourceStartPosition.traverse(region.sourceTraversal)
      targetStartPosition = targetStartPosition.traverse(region.targetTraversal)
      regions.push(region)

    regions

  sourceDidChange: ({startPosition, oldExtent, newExtent}) ->
    endPosition = startPosition.traverse(oldExtent)
    sourceTraversal = Point.ZERO
    targetTraversal = Point.ZERO

    invalidatedRegionsStartIndex = null
    invalidatedRegionsStartPosition = null

    for region, index in @regions
      break if sourceTraversal.compare(endPosition) > 0

      if sourceTraversal.compare(startPosition) >= 0
        invalidatedRegionsStartIndex ?= index
        invalidatedRegionsStartPosition ?= sourceTraversal

      sourceTraversal = sourceTraversal.traverse(region.sourceTraversal)
      targetTraversal = targetTraversal.traverse(region.targetTraversal)

    invalidatedRegionsEndIndex = index
    invalidatedRegionsEndPosition = sourceTraversal

    extentDelta = oldExtent.traversal(newExtent)
    replacementRegionsEndPosition = invalidatedRegionsEndPosition.traverse(extentDelta)

    replacementRegions = @buildRegions(invalidatedRegionsStartPosition, replacementRegionsEndPosition)
    count = invalidatedRegionsEndIndex - invalidatedRegionsStartIndex
    @regions.splice(invalidatedRegionsStartIndex, count, replacementRegions...)

  getContent: ->
    @slice(Point.ZERO, @getEndPosition())

  fromPositionInLayer: (position, layer) ->
    return position if position.isEqual(Point.ZERO)

    if @source isnt layer
      sourcePosition = @source.fromPositionInLayer(position, layer)
    else
      sourcePosition = position

    sourceTraversal = Point.ZERO
    targetTraversal = Point.ZERO

    for region in @regions
      nextSourceTraversal = sourceTraversal.traverse(region.sourceTraversal)
      break if nextSourceTraversal.isGreaterThan(sourcePosition)
      sourceTraversal = nextSourceTraversal
      targetTraversal = targetTraversal.traverse(region.targetTraversal)

    overshoot = sourceTraversal.traversal(sourcePosition)
    targetTraversal.traverse(overshoot)

  toPositionInLayer: (position, layer, options) ->
    return position if position.isEqual(Point.ZERO)

    targetPosition = position

    sourceTraversal = Point.ZERO
    targetTraversal = Point.ZERO

    for region in @regions
      nextTargetTraversal = targetTraversal.traverse(region.targetTraversal)
      nextSourceTraversal = sourceTraversal.traverse(region.sourceTraversal)
      break if nextTargetTraversal.isGreaterThan(targetPosition)
      targetTraversal = nextTargetTraversal
      sourceTraversal = nextSourceTraversal

    if region.clip and targetTraversal.isLessThan(position)
      if options?.clip is 'forward'
        sourcePosition = nextSourceTraversal
      else
        sourcePosition = sourceTraversal
    else
      overshoot = targetTraversal.traversal(targetPosition)
      sourcePosition = sourceTraversal.traverse(overshoot)

      if sourcePosition.compare(nextSourceTraversal) >= 0
        if options?.clip is 'forward'
          sourcePosition = nextSourceTraversal
        else
          sourcePosition = nextSourceTraversal
          if sourceTraversal.isLessThan(nextSourceTraversal)
            sourcePosition = sourcePosition.traverse(Point(0, -1))

      sourcePosition = @source.clipPosition(sourcePosition, options?.clip)

    if @source isnt layer
      @source.toPositionInLayer(sourcePosition, layer)
    else
      sourcePosition

  clipPosition: (position, direction='backward') ->
    {rows, columns} = position
    rows = Math.max(0, rows)
    columns = Math.max(0, columns)
    position = Point(rows, columns)
    @fromPositionInLayer(@toPositionInLayer(position, @source, clip: direction), @source)

  positionOf: (string, start=Point(0, 0)) ->
    if sourcePosition = @source.positionOf(string, @toPositionInLayer(start, @source))
      @fromPositionInLayer(sourcePosition, @source)

  characterAt: (position) ->
    @slice(position, position.traverse(Point(0, 1)))

  slice: (start, end=@getEndPosition()) ->
    contentStart = null
    contentEnd = null
    content = ""

    targetTraversal = Point.ZERO
    sourceTraversal = Point.ZERO

    for region in @regions
      break if targetTraversal.compare(end) >= 0

      nextTargetTraversal = targetTraversal.traverse(region.targetTraversal)
      nextSourceTraversal = sourceTraversal.traverse(region.sourceTraversal)

      if nextTargetTraversal.isGreaterThan(start)
        if start.isGreaterThan(targetTraversal)
          targetStartPosition = start
          sourceStartPosition = sourceTraversal.traverse(targetTraversal.traversal(start))
        else
          targetStartPosition = targetTraversal
          sourceStartPosition = sourceTraversal

        if end.isLessThan(nextTargetTraversal)
          targetEndPosition = end
          sourceEndPosition = sourceTraversal.traverse(targetTraversal.traversal(end))
        else
          targetEndPosition = nextTargetTraversal
          sourceEndPosition = nextSourceTraversal

        content += @transform.getContent({sourceStartPosition, targetStartPosition, sourceEndPosition, targetEndPosition})

      targetTraversal = nextTargetTraversal
      sourceTraversal = nextSourceTraversal

    content

  getEndPosition: ->
    targetTraversal = Point.ZERO
    for region in @regions
      targetTraversal = targetTraversal.traverse(region.targetTraversal)
    targetTraversal
